"""
LangGraph state machines for Vino Trip AI agents.

Graphs:
- palate: Analyze tasting notes → structured profile (stub)
- trip: Aggregate group preferences → search → itinerary (stub)
- trip_planner: Conversational trip planner with tool-calling (active)
"""

import operator
from typing import Annotated, TypedDict

from langchain_core.messages import BaseMessage
from langgraph.graph import END, START, StateGraph


class VinoState(TypedDict):
    """Shared state for palate/trip graphs (legacy stubs)."""
    user_id: str
    palate_profile: dict
    trip_context: dict
    messages: list[BaseMessage]
    current_wines: list[dict]
    pinecone_results: list[dict]
    itinerary_draft: list[dict]


class TripPlannerState(TypedDict):
    """State for the conversational trip planner agent."""

    # Identity
    user_id: str

    # Message history (appended via operator.add reducer)
    messages: Annotated[list[BaseMessage], operator.add]

    # Planning phase
    phase: str  # gathering | searching | proposing | revising | approved | rejected

    # Gathered requirements from conversation
    requirements: dict  # {region, date, group_size, preferences, budget, duration, place_types}

    # Places found by search tool
    candidate_places: list[dict]

    # The proposed trip for preview (set by propose node)
    proposed_trip: dict  # {name, description, scheduled_date, stops: [...]}

    # Result after commit
    created_trip_id: str


# ---------------------------------------------------------------------------
# Stub nodes for legacy graphs
# ---------------------------------------------------------------------------

def analyze_palate(state: VinoState) -> dict:
    return {}

def search_wineries(state: VinoState) -> dict:
    return {}

def aggregate_group_palate(state: VinoState) -> dict:
    return {}

def build_itinerary(state: VinoState) -> dict:
    return {}

def process_label_image(state: VinoState) -> dict:
    return {}


# ---------------------------------------------------------------------------
# Trip Planner nodes (imported from nodes.py)
# ---------------------------------------------------------------------------

def build_trip_planner_graph() -> StateGraph:
    """Build the conversational trip planner graph."""
    from .nodes import planner_commit, planner_conversation, planner_route

    builder = StateGraph(TripPlannerState)

    builder.add_node("conversation", planner_conversation)
    builder.add_node("commit", planner_commit)

    # Entry: always start with conversation
    builder.add_edge(START, "conversation")

    # After conversation, route based on phase
    builder.add_conditional_edges(
        "conversation",
        planner_route,
        {
            "continue": END,      # Pause for user input (normal chat turn)
            "commit": "commit",   # User approved — create the trip
            "done": END,          # Rejected or error
        },
    )

    builder.add_edge("commit", END)

    return builder


# ---------------------------------------------------------------------------
# Legacy graph builders
# ---------------------------------------------------------------------------

def build_palate_graph() -> StateGraph:
    builder = StateGraph(VinoState)
    builder.add_node("analyze_palate", analyze_palate)
    builder.add_node("search_wineries", search_wineries)
    builder.add_edge(START, "analyze_palate")
    builder.add_edge("analyze_palate", "search_wineries")
    builder.add_edge("search_wineries", END)
    return builder


def build_trip_graph() -> StateGraph:
    builder = StateGraph(VinoState)
    builder.add_node("aggregate_group_palate", aggregate_group_palate)
    builder.add_node("search_wineries", search_wineries)
    builder.add_node("build_itinerary", build_itinerary)
    builder.add_edge(START, "aggregate_group_palate")
    builder.add_edge("aggregate_group_palate", "search_wineries")
    builder.add_edge("search_wineries", "build_itinerary")
    builder.add_edge("build_itinerary", END)
    return builder


# ---------------------------------------------------------------------------
# Graph compilation with PostgreSQL checkpointing
# ---------------------------------------------------------------------------

_compiled_graphs: dict = {}


def get_compiled_graph(graph_name: str = "palate"):
    """Compile a graph with PostgreSQL checkpointing.

    Uses DATABASE_URL_DIRECT (bypasses PgBouncer) for the psycopg connection.
    Caches compiled graphs to avoid leaking connections.
    """
    if graph_name in _compiled_graphs:
        return _compiled_graphs[graph_name]

    import psycopg
    from django.conf import settings
    from langgraph.checkpoint.postgres import PostgresSaver

    builders = {
        "palate": build_palate_graph,
        "trip": build_trip_graph,
        "trip_planner": build_trip_planner_graph,
    }

    builder = builders[graph_name]()

    # Use direct connection (bypasses PgBouncer for DDL and checkpointing)
    db_url = getattr(settings, "DATABASE_URL_DIRECT", settings.DATABASE_URL)
    if db_url.startswith("postgres://"):
        db_url = db_url.replace("postgres://", "postgresql://", 1)

    # Add SSL for non-local connections
    connect_kwargs = {"autocommit": True}
    if not settings.DEBUG:
        connect_kwargs["sslmode"] = "require"

    conn = psycopg.connect(db_url, **connect_kwargs)
    checkpointer = PostgresSaver(conn)
    checkpointer.setup()

    compiled = builder.compile(checkpointer=checkpointer)
    _compiled_graphs[graph_name] = compiled
    return compiled
