"""
LangGraph state machine for VinoVoyage AI agents.

The graph orchestrates multi-step AI workflows:
- Palate analysis (Claude analyzes tasting notes → structured profile)
- Trip planning (aggregate group preferences → select wineries → build itinerary)
- Semantic search (query Pinecone for winery/wine recommendations)

State is checkpointed to PostgreSQL between nodes via langgraph-checkpoint-postgres,
so conversations and multi-step workflows survive across requests.
"""

from typing import TypedDict

from langchain_core.messages import BaseMessage
from langgraph.graph import END, START, StateGraph


class VinoState(TypedDict):
    """Shared state that flows through all graph nodes."""

    # Identity
    user_id: str  # UUID of the current user

    # Palate Profile — structured taste preferences built by Claude
    palate_profile: dict  # {sweetness, acidity, body, tannins, flavor_notes, ...}

    # Current Trip Context — populated when planning a trip
    trip_context: dict  # {trip_id, member_ids, constraints, scheduled_date, ...}

    # Message history for multi-turn agent conversations
    messages: list[BaseMessage]

    # Working data for in-flight nodes
    current_wines: list[dict]  # wines under consideration
    pinecone_results: list[dict]  # RAG retrieval results
    itinerary_draft: list[dict]  # proposed winery stops with ordering


# ---------------------------------------------------------------------------
# Node stubs — each will be implemented as its own function in nodes.py
# ---------------------------------------------------------------------------

def analyze_palate(state: VinoState) -> dict:
    """Use Claude to analyze tasting notes into a structured palate profile."""
    # TODO: implement with ChatAnthropic
    return {}


def search_wineries(state: VinoState) -> dict:
    """Query Pinecone for wineries matching the palate profile."""
    # TODO: implement with Pinecone client
    return {}


def aggregate_group_palate(state: VinoState) -> dict:
    """Merge palate profiles of trip members into a group preference."""
    # TODO: implement with ChatAnthropic
    return {}


def build_itinerary(state: VinoState) -> dict:
    """Plan an ordered winery route factoring in distance and preferences."""
    # TODO: implement with ChatAnthropic + geopy
    return {}


def process_label_image(state: VinoState) -> dict:
    """Use Gemini Vision to extract wine details from a label photo."""
    # TODO: implement with ChatGoogleGenerativeAI
    return {}


# ---------------------------------------------------------------------------
# Graph definition
# ---------------------------------------------------------------------------

def build_palate_graph() -> StateGraph:
    """Build the palate analysis graph (Phase 1 workflow)."""
    builder = StateGraph(VinoState)
    builder.add_node("analyze_palate", analyze_palate)
    builder.add_node("search_wineries", search_wineries)

    builder.add_edge(START, "analyze_palate")
    builder.add_edge("analyze_palate", "search_wineries")
    builder.add_edge("search_wineries", END)

    return builder


def build_trip_graph() -> StateGraph:
    """Build the trip planning graph (Phase 2 workflow)."""
    builder = StateGraph(VinoState)
    builder.add_node("aggregate_group_palate", aggregate_group_palate)
    builder.add_node("search_wineries", search_wineries)
    builder.add_node("build_itinerary", build_itinerary)

    builder.add_edge(START, "aggregate_group_palate")
    builder.add_edge("aggregate_group_palate", "search_wineries")
    builder.add_edge("search_wineries", "build_itinerary")
    builder.add_edge("build_itinerary", END)

    return builder


def get_compiled_graph(graph_name: str = "palate"):
    """
    Compile a graph with PostgreSQL checkpointing.

    Usage:
        graph = get_compiled_graph("palate")
        result = graph.invoke(
            initial_state,
            config={"configurable": {"thread_id": str(user.id)}}
        )
    """
    from django.conf import settings
    from langgraph.checkpoint.postgres import PostgresSaver

    checkpointer = PostgresSaver.from_conn_string(settings.DATABASE_URL)
    checkpointer.setup()  # Creates checkpoint tables if they don't exist

    builders = {
        "palate": build_palate_graph,
        "trip": build_trip_graph,
    }

    builder = builders[graph_name]()
    return builder.compile(checkpointer=checkpointer)
