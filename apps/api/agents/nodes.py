"""
Node implementations for the Vino Trip Planner LangGraph.

The planner uses a conversational agent pattern:
1. conversation node — Claude with tool-calling gathers requirements and proposes trips
2. commit node — creates Trip + TripStops in the database on user approval
"""

import json
import logging
from datetime import date, datetime, time, timedelta

from langchain_core.messages import AIMessage, HumanMessage, SystemMessage

logger = logging.getLogger(__name__)

PLANNER_SYSTEM_PROMPT = """You are Sippy, a friendly and expert trip planning assistant for Vino, a wine, beer, and food tasting app.

TODAY'S DATE: {today}

Your job is to help users plan amazing tasting trips through conversation. Here's how you work:

## GATHERING PHASE — ONE QUESTION AT A TIME

The app shows users a checklist of what you need before they start chatting. Your job is to fill in the gaps from their first message.

Required info (with defaults if not provided):
1. Where? — Region/location (REQUIRED, no default)
2. When? — Date (REQUIRED — convert "today"/"tomorrow"/"this Saturday" to YYYY-MM-DD)
3. What time to start? — (default: 10:30 AM)
4. How many stops? — (default: 3-4)
5. How long at each stop? — (default: 60 min)
6. Max drive time between stops? — (default: 20 min)
7. What do you like? — Wine/beer styles, preferences
8. Events or live music? — (default: yes if available)

CRITICAL RULES FOR ASKING QUESTIONS:
- After the user's first message, ALWAYS ask at least ONE follow-up question before searching — even if they gave lots of detail
- Ask only ONE missing question per response — never list multiple questions
- Keep each response to 1-2 sentences: briefly acknowledge what they said, then ask the ONE next question
- Pick the most important unanswered question from this priority order:
  1. What do you like? (wine styles, beer types) — if not mentioned
  2. How long at each stop? — if not mentioned
  3. Max drive time between stops? — if not mentioned
  4. Events or live music? — if not mentioned
  5. Any dietary needs or must-visit places? — if not mentioned
- Skip questions they already answered — never repeat back what they told you
- After asking 1-2 follow-up questions, start searching — use defaults for anything still missing
- Do NOT search on the very first response. Always ask at least one question first.

## SEARCHING PHASE
Once you have enough info (at minimum: region, date, preferences, start time, and stop duration), use the search_places tool to find options. Call it multiple times with different queries to get variety. Factor in their max drive time between stops when selecting places.

IMPORTANT: The search_places tool returns image_url for each place. You MUST include these image URLs in your trip plan — do NOT replace them with empty strings.

## PROPOSING PHASE
When you have good candidates, build a trip itinerary. Present it as a clear plan with:
- A fun trip name
- Each stop with: place name, city, why it's a good pick, estimated time there
- Suggested order based on geography and minimal drive time
- Realistic arrival times using THEIR requested start time and stop duration
- Mention any events, live music, or specials you found

CRITICAL: When you're ready to propose a trip, you MUST include a JSON block wrapped in <trip_plan> tags at the END of your message. This is how the app knows to show the preview. Format:

<trip_plan>
{{
  "name": "Trip Name Here",
  "description": "Brief description",
  "scheduled_date": "YYYY-MM-DD",
  "end_date": "YYYY-MM-DD",
  "stops": [
    {{
      "place": {{
        "name": "Place Name",
        "city": "City",
        "state": "ST",
        "place_type": "winery",
        "address": "123 Main St",
        "latitude": 38.5,
        "longitude": -122.5,
        "website": "https://...",
        "description": "About this place",
        "image_url": "https://actual-image-url-from-search-results"
      }},
      "order": 0,
      "duration_minutes": 90,
      "arrival_time": "10:00",
      "notes": "Why this stop is great for this trip"
    }}
  ]
}}
</trip_plan>

DATE AND TIME RULES:
- scheduled_date and end_date MUST be real dates in YYYY-MM-DD format
- If the user says "today", use {today}
- If the user says "tomorrow", use the day after {today}
- If the user says "this Saturday", calculate the actual date from {today}
- For single-day trips, end_date equals scheduled_date
- arrival_time is in HH:MM 24-hour format
- Space stops ~60-90 minutes apart plus drive time
- First stop typically arrives around 10:00-11:00 AM

## REVISING
If the user wants changes after seeing the preview, adjust the plan and propose again with updated <trip_plan> tags.

## RULES
- Be warm, enthusiastic, and knowledgeable
- Keep responses concise (3-5 sentences for questions, more detail for proposals)
- Always use the search_places tool before proposing — never invent places
- Include real data from search results (addresses, descriptions, image URLs)
- ALWAYS include the image_url from search results — never leave it empty if the search returned one
- NEVER say you are creating or building the trip — you can only PROPOSE plans via <trip_plan> tags
- The user must click a button in the app to approve — you cannot approve on their behalf
- If the user says "looks good", "yes", "go ahead" etc., respond with "Great! Click the 'Looks Good!' button below the preview to create your trip!" and include the SAME <trip_plan> block again
- IMPORTANT: Whenever you suggest ANY change to the trip plan (swapping a stop, changing times, etc.), you MUST include the COMPLETE updated <trip_plan> JSON block with ALL stops. Never describe changes without including the full updated plan in <trip_plan> tags. The app can ONLY display previews from <trip_plan> tags — if you don't include them, the user will see the old plan.
"""


def planner_conversation(state: dict) -> dict:
    """Core conversation node — runs Claude with tools and the planner system prompt."""
    from apps.api.ai_utils import get_claude
    from .tools import search_places, get_drive_time

    llm = get_claude()
    tools = [search_places, get_drive_time]
    llm_with_tools = llm.bind_tools(tools)

    # Build system prompt with today's date
    today_str = date.today().isoformat()
    system_content = PLANNER_SYSTEM_PROMPT.format(today=today_str)

    # Add palate context if available
    user_id = state.get("user_id")
    if user_id:
        try:
            from apps.palate.models import PalateProfile
            profile = PalateProfile.objects.filter(user_id=user_id).first()
            if profile and profile.preferences:
                system_content += f"\n\n## User's Palate Profile\n{json.dumps(profile.preferences, indent=2)}"
        except Exception:
            pass

    # Build message list — strip ALL tool-related content from history
    # to avoid mismatched tool_use/tool_result pairs across turns.
    # AIMessage.content can be a string OR a list of content blocks
    # (including tool_use blocks). We must extract only plain text.
    from langchain_core.messages import ToolMessage

    def _extract_text(msg_content) -> str:
        """Extract plain text from message content (string or content blocks list)."""
        if isinstance(msg_content, str):
            return msg_content
        if isinstance(msg_content, list):
            parts = []
            for block in msg_content:
                if isinstance(block, dict) and block.get("type") == "text":
                    parts.append(block.get("text", ""))
                elif isinstance(block, str):
                    parts.append(block)
            return "\n".join(parts)
        return str(msg_content) if msg_content else ""

    messages = [SystemMessage(content=system_content)]
    for msg in state.get("messages", []):
        if isinstance(msg, ToolMessage):
            continue
        if isinstance(msg, AIMessage):
            text = _extract_text(msg.content)
            if text.strip():
                messages.append(AIMessage(content=text))
            continue
        messages.append(msg)

    # If we already have a proposed trip and the user is asking for changes,
    # append the current plan to the system prompt so Claude can modify it
    current_phase = state.get("phase", "gathering")
    current_proposed = state.get("proposed_trip")
    if current_phase == "proposing" and current_proposed:
        plan_context = (
            "\n\n## CURRENT TRIP PLAN (user is requesting changes)\n"
            "You MUST include the COMPLETE updated <trip_plan> JSON block in your response "
            "with ALL stops. Here is the current plan to modify:\n\n"
            + json.dumps(current_proposed, indent=2)
        )
        # Update the system message (first in the list) to include the plan
        messages[0] = SystemMessage(content=messages[0].content + plan_context)

    # Invoke LLM with tools — handle tool calls in a loop
    tool_map = {t.name: t for t in tools}
    max_tool_rounds = 5
    for _ in range(max_tool_rounds):
        response = llm_with_tools.invoke(messages)
        messages.append(response)

        if not response.tool_calls:
            break

        for tc in response.tool_calls:
            tool_fn = tool_map.get(tc["name"])
            if tool_fn:
                try:
                    result = tool_fn.invoke(tc["args"])
                    tool_msg = ToolMessage(
                        content=json.dumps(result, default=str),
                        tool_call_id=tc["id"],
                    )
                except Exception as e:
                    tool_msg = ToolMessage(
                        content=f"Tool error: {e}",
                        tool_call_id=tc["id"],
                    )
            else:
                tool_msg = ToolMessage(
                    content=f"Unknown tool: {tc['name']}",
                    tool_call_id=tc["id"],
                )
            messages.append(tool_msg)

    # Ensure the final message is a text-only AI response
    final_response = messages[-1]
    needs_text_response = (
        not isinstance(final_response, AIMessage)
        or getattr(final_response, "tool_calls", None)
    )
    if needs_text_response:
        # Call LLM WITH tools to get a proper continuation after tool results.
        # The tool results are in the messages, so Claude needs to see them
        # and respond with text (and possibly more tool calls).
        continuation = llm_with_tools.invoke(messages)
        messages.append(continuation)

        # If it STILL wants to call tools, do one final round
        if getattr(continuation, "tool_calls", None):
            for tc in continuation.tool_calls:
                tool_fn = tool_map.get(tc["name"])
                if tool_fn:
                    try:
                        result = tool_fn.invoke(tc["args"])
                        messages.append(ToolMessage(
                            content=json.dumps(result, default=str),
                            tool_call_id=tc["id"],
                        ))
                    except Exception as e:
                        messages.append(ToolMessage(
                            content=f"Tool error: {e}",
                            tool_call_id=tc["id"],
                        ))

            # Now force a text-only response
            final_response = llm.invoke([
                m for m in messages
                if not isinstance(m, ToolMessage)
                and not (isinstance(m, AIMessage) and getattr(m, "tool_calls", None))
            ])
            messages.append(final_response)
        else:
            final_response = continuation

    # Extract text content (handles both string and content block list)
    content = _extract_text(final_response.content)
    proposed_trip = state.get("proposed_trip")
    phase = state.get("phase", "gathering")

    if "<trip_plan>" in content and "</trip_plan>" in content:
        try:
            plan_json = content.split("<trip_plan>")[1].split("</trip_plan>")[0].strip()
            proposed_trip = json.loads(plan_json)
            phase = "proposing"
        except (json.JSONDecodeError, IndexError):
            logger.warning("Failed to parse trip_plan JSON from response")

    # Strip the <trip_plan> tags from the display message
    display_content = content
    if "<trip_plan>" in display_content:
        before = display_content.split("<trip_plan>")[0]
        after = display_content.split("</trip_plan>")[-1] if "</trip_plan>" in display_content else ""
        display_content = (before + after).strip()

    # Strip any tool-related XML tags that Claude may output inline
    # (e.g. <search_places>, <get_drive_time>, etc.)
    import re
    display_content = re.sub(
        r'<(search_places|get_drive_time|tool_call|function_call)[^>]*>.*?</\1>',
        '', display_content, flags=re.DOTALL,
    )
    # Also strip self-closing or unclosed tool tags with JSON content
    display_content = re.sub(
        r'<(search_places|get_drive_time)[^>]*>\s*\{[^}]*\}[\s\S]*?(?:</\1>|(?=\n\n))',
        '', display_content, flags=re.DOTALL,
    )
    # Clean up extra whitespace left behind
    display_content = re.sub(r'\n{3,}', '\n\n', display_content).strip()

    # Only persist the user's message and the final AI response (clean)
    # Do NOT persist intermediate tool_call/tool_result messages —
    # they cause errors when replayed across turns
    new_messages = []
    original_msg_count = len(state.get("messages", []))
    # The first new message after system + history is the user's HumanMessage (if any)
    start_idx = 1 + original_msg_count
    for msg in messages[start_idx:]:
        if isinstance(msg, HumanMessage):
            new_messages.append(msg)
    # Always add the clean final AI response
    new_messages.append(AIMessage(content=display_content))

    # NOTE: Approval is ONLY triggered by the explicit action='approve' from the
    # Flutter UI button, which sets phase='approved' in the input_state before
    # invoking the graph. We never auto-detect approval from conversational
    # phrases — the user MUST see a preview and click "Looks Good!" first.

    return {
        "messages": new_messages,
        "proposed_trip": proposed_trip,
        "phase": phase,
    }


def planner_route(state: dict) -> str:
    """Route after conversation — decide next step based on phase."""
    phase = state.get("phase", "gathering")

    if phase == "approved":
        return "commit"
    if phase == "rejected":
        return "done"
    return "continue"


def planner_commit(state: dict) -> dict:
    """Create the Trip and TripStops from the proposed plan."""
    from django.utils import timezone

    from apps.trips.models import Trip, TripMember, TripStop
    from apps.wineries.models import Place

    proposed = state.get("proposed_trip")
    user_id = state.get("user_id")

    if not proposed or not user_id:
        return {
            "messages": [AIMessage(content="Something went wrong — no trip plan to create. Let's try again!")],
            "phase": "gathering",
        }

    try:
        # Parse dates
        scheduled_date = None
        end_date = None
        if proposed.get("scheduled_date"):
            try:
                scheduled_date = date.fromisoformat(proposed["scheduled_date"])
            except ValueError:
                scheduled_date = date.today()
        if proposed.get("end_date"):
            try:
                end_date = date.fromisoformat(proposed["end_date"])
            except ValueError:
                end_date = scheduled_date

        # Create Trip
        trip = Trip.objects.create(
            name=proposed.get("name", "Sippy's Trip"),
            description=proposed.get("description", ""),
            created_by_id=user_id,
            status=Trip.Status.PLANNING,
            scheduled_date=scheduled_date,
            end_date=end_date,
        )

        # Add creator as organizer
        TripMember.objects.create(
            trip=trip,
            user_id=user_id,
            role=TripMember.Role.ORGANIZER,
            rsvp_status="accepted",
        )

        # Create stops with arrival times
        created_stops = []  # list of (TripStop, Place) for drive time calc
        for stop_data in proposed.get("stops", []):
            place_data = stop_data.get("place", {})
            place_name = place_data.get("name", "")

            if not place_name:
                continue

            # Find or create place
            place = Place.objects.filter(
                name__iexact=place_name, is_active=True
            ).first()

            if not place:
                place = Place.objects.create(
                    name=place_name,
                    place_type=place_data.get("place_type", "winery"),
                    address=place_data.get("address", ""),
                    city=place_data.get("city", ""),
                    state=place_data.get("state", ""),
                    latitude=place_data.get("latitude"),
                    longitude=place_data.get("longitude"),
                    website=place_data.get("website", ""),
                    description=place_data.get("description", ""),
                    image_url=place_data.get("image_url", ""),
                )
            else:
                # Update image_url if the existing place doesn't have one
                new_image = place_data.get("image_url", "")
                if new_image and not place.image_url:
                    place.image_url = new_image
                    place.save(update_fields=["image_url", "updated_at"])

            # Parse arrival_time
            arrival_time_dt = None
            arrival_time_str = stop_data.get("arrival_time", "")
            if arrival_time_str and scheduled_date:
                try:
                    t = time.fromisoformat(arrival_time_str)
                    naive_dt = datetime.combine(scheduled_date, t)
                    arrival_time_dt = timezone.make_aware(naive_dt)
                except (ValueError, TypeError):
                    pass

            trip_stop = TripStop.objects.create(
                trip=trip,
                place=place,
                order=stop_data.get("order", 0),
                duration_minutes=stop_data.get("duration_minutes"),
                arrival_time=arrival_time_dt,
                notes=stop_data.get("notes", ""),
            )
            created_stops.append((trip_stop, place))

        # Calculate drive times between consecutive stops
        if len(created_stops) > 1:
            from .tools import get_drive_time
            for i in range(1, len(created_stops)):
                prev_stop, prev_place = created_stops[i - 1]
                curr_stop, curr_place = created_stops[i]

                if (prev_place.latitude and prev_place.longitude
                        and curr_place.latitude and curr_place.longitude):
                    try:
                        drive_info = get_drive_time.invoke({
                            "origin_lat": float(prev_place.latitude),
                            "origin_lng": float(prev_place.longitude),
                            "dest_lat": float(curr_place.latitude),
                            "dest_lng": float(curr_place.longitude),
                        })
                        if drive_info.get("drive_minutes"):
                            curr_stop.travel_minutes = drive_info["drive_minutes"]
                        if drive_info.get("miles"):
                            curr_stop.travel_miles = drive_info["miles"]
                        curr_stop.save(update_fields=[
                            "travel_minutes", "travel_miles", "updated_at",
                        ])
                    except Exception:
                        logger.warning(
                            "Drive time calc failed for stop %s → %s",
                            prev_place.name, curr_place.name,
                        )

        trip_id = str(trip.id)
        stop_count = trip.trip_stops.count()
        return {
            "messages": [AIMessage(
                content=f"Your trip \"{trip.name}\" has been created with "
                        f"{stop_count} stops! "
                        f"Drive times and distances have been calculated between each stop. "
                        f"Head over to your trip to see all the details, invite friends, and start exploring."
            )],
            "created_trip_id": trip_id,
            "phase": "approved",
        }

    except Exception:
        logger.exception("Failed to create trip from plan")
        return {
            "messages": [AIMessage(content="Oops, I had trouble creating the trip. Let's try again!")],
            "phase": "gathering",
        }
