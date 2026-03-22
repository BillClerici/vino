import logging
import time

from rest_framework import status
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.viewsets import ModelViewSet

from apps.trips.models import SippyConversation
from ..permissions import HasActiveSubscription
from .serializers import (
    SippyConversationDetailSerializer,
    SippyConversationListSerializer,
    SippyConversationWriteSerializer,
)

logger = logging.getLogger(__name__)


class SippyConversationViewSet(ModelViewSet):
    permission_classes = [HasActiveSubscription]
    ordering = ["-updated_at"]

    def get_queryset(self):
        qs = SippyConversation.objects.filter(
            user=self.request.user, is_active=True
        )
        # Optional filters
        chat_type = self.request.query_params.get("chat_type")
        if chat_type:
            qs = qs.filter(chat_type=chat_type)
        trip_id = self.request.query_params.get("trip")
        if trip_id:
            qs = qs.filter(trip_id=trip_id)
        return qs

    def get_serializer_class(self):
        if self.action == "list":
            return SippyConversationListSerializer
        if self.action in ("create", "update", "partial_update"):
            return SippyConversationWriteSerializer
        return SippyConversationDetailSerializer

    def perform_create(self, serializer):
        messages = serializer.validated_data.get("messages", [])
        title = serializer.validated_data.get("title", "")
        if not title and messages:
            first_user = next(
                (m for m in messages if m.get("role") == "user"), None
            )
            if first_user:
                title = first_user["content"][:60]
        serializer.save(user=self.request.user, title=title)

    def perform_destroy(self, instance):
        instance.is_active = False
        instance.save(update_fields=["is_active", "updated_at"])

    @action(detail=True, methods=["post"])
    def retry(self, request, pk=None):
        """Retry the last user message in this conversation."""
        conversation = self.get_object()
        messages = conversation.messages or []

        # Find last user message
        last_user_msg = None
        for msg in reversed(messages):
            if msg.get("role") == "user":
                last_user_msg = msg
                break

        if not last_user_msg:
            return Response(
                {"detail": "No user message to retry."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Remove failed assistant response if it's the last message
        if messages and messages[-1].get("role") == "assistant":
            messages.pop()

        user_text = last_user_msg["content"]

        if conversation.chat_type == "plan":
            return self._retry_plan(request, conversation, user_text, messages)
        else:
            return self._retry_ask(request, conversation, user_text, messages)

    def _retry_plan(self, request, conversation, user_text, messages):
        """Retry a planner conversation."""
        try:
            from apps.api.agents.graph import get_compiled_graph
            from langchain_core.messages import AIMessage, HumanMessage

            session_id = conversation.session_id
            if not session_id:
                session_id = f"plan:{request.user.id}:{int(time.time())}"
                conversation.session_id = session_id

            graph = get_compiled_graph("trip_planner")
            config = {"configurable": {"thread_id": session_id}}

            result = graph.invoke(
                {
                    "messages": [HumanMessage(content=user_text)],
                    "user_id": str(request.user.id),
                },
                config,
            )

            reply = ""
            for msg in reversed(result.get("messages", [])):
                if isinstance(msg, AIMessage):
                    reply = msg.content
                    break

            # Update conversation
            messages.append({"role": "assistant", "content": reply})
            conversation.messages = messages
            conversation.phase = result.get("phase", conversation.phase)
            if result.get("proposed_trip"):
                conversation.proposed_trip = result["proposed_trip"]
            conversation.save(update_fields=[
                "messages", "phase", "proposed_trip", "session_id", "updated_at",
            ])

            return Response({
                "reply": reply,
                "phase": result.get("phase", "gathering"),
                "session_id": session_id,
                "proposed_trip": result.get("proposed_trip"),
                "trip_id": result.get("created_trip_id"),
                "conversation_id": str(conversation.id),
            })

        except Exception:
            logger.exception("Retry plan failed")
            return Response(
                {"detail": "Retry failed. Please try again."},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )

    def _retry_ask(self, request, conversation, user_text, messages):
        """Retry an Ask Sippy conversation."""
        try:
            from apps.api.ai_utils import get_claude
            from langchain_core.messages import (
                AIMessage,
                HumanMessage,
                SystemMessage,
            )

            # Rebuild context (simplified — trip chat context)
            trip = conversation.trip
            system_content = (
                "You are Sippy, a friendly AI sommelier and trip assistant. "
                "Keep responses conversational and concise."
            )

            llm = get_claude()
            llm_messages = [SystemMessage(content=system_content)]

            # Add history
            for msg in messages[-10:]:
                role = msg.get("role", "")
                content = msg.get("content", "")
                if role == "user":
                    llm_messages.append(HumanMessage(content=content))
                elif role == "assistant":
                    llm_messages.append(AIMessage(content=content))

            llm_messages.append(HumanMessage(content=user_text))
            response = llm.invoke(llm_messages)
            reply = response.content

            messages.append({"role": "assistant", "content": reply})
            conversation.messages = messages
            conversation.save(update_fields=["messages", "updated_at"])

            return Response({
                "reply": reply,
                "conversation_id": str(conversation.id),
            })

        except Exception:
            logger.exception("Retry ask failed")
            return Response(
                {"detail": "Retry failed. Please try again."},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )
