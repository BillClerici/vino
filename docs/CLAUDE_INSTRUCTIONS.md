# Project: Vino Trip - Agentic Wine & Winery Companion
## Technical Stack Overview
- **Backend/Web:** Django (REST Framework for Mobile API)
- **Mobile:** Flutter
- **AI Orchestration:** LangChain & LangGraph (Python-based)
- **Primary LLM:** Anthropic Claude 3.5 Sonnet (Reasoning, Logic, Tool Use)
- **Vision LLM:** Google Gemini 1.5 Pro (Label & Menu OCR, Image Reasoning)
- **Database:** PostgreSQL
- **Vector Search:** Pinecone (For Palate/Wine Embeddings)
- **Infrastructure:** Docker (Containerized Django & Worker services)

## Initial Project Setup Instructions
1. **Dockerize Django:** Use the existing Django & PostgreSQL Docker setup.
2. **Database Schema:** Initialize PostgreSQL tables for `Wineries`, `Drinks`, `Visits`, and `Trips` and connect to existing 'User' table.
3. **LangGraph State Definition:** Define a `PalateState` TypedDict to track user preferences (Tannins, Acidity, Body, Ambience Score).
4. **Pinecone Integration:** Set up the index for "Wine-Embeddings" using Anthropic-compatible embedding headers or LangChain's VoyageAI/OpenAI embedding wrappers.

## Core Implementation Goal
Build a "Vision-to-Log" pipeline:
- **Input:** Image (Wine Label) + Text/Voice Note.
- **Processing:** Gemini 1.5 Pro extracts metadata from image -> Claude 3.5 Sonnet maps metadata to user preferences -> LangGraph updates "Palate State" -> Persist in PostgreSQL.

## Coding Style Guidelines
- Use **Claude 3.5 Sonnet** for all complex mapping, itinerary generation, and social coordination logic.
- Use **Gemini 1.5 Pro** strictly for visual processing and multimodal extraction.
- Maintain **LangGraph** nodes as pure functions.
- Use **pydantic** for all structured outputs from Claude (Itineraries, Tasting Notes).