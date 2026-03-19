# VinoVoyage Feature Roadmap

## Phase 1: The Digital Sommelier (Logging & Memory)
- [ ] **Vision Intake:** Capture wine label via Flutter, process via **Gemini 1.5 Pro**.
- [ ] **The "Palate" Profile:** Use **Claude 3.5 Sonnet** to translate tasting notes into structured vector data.
- [ ] **Check-in System:** Log Winery name, staff rating, and ambience via Claude's sentiment analysis.
- [ ] **Semantic Search:** Implement RAG using Pinecone to find wineries matching specific "vibe" descriptions.

## Phase 2: Social & Trip Planning (LangGraph Orchestration)
- [ ] **Invitation System:** **Claude** generates personalized invitation text based on friend's taste history.
- [ ] **Group Palate Aggregator:** A LangGraph node where **Claude** identifies overlapping preferences for a group.
- [ ] **Itinerary Agent:**
    - [ ] Routing logic (Distance/Time between wineries).
    - [ ] **Claude** selects wineries that best fit the group's aggregate "Palate State."
    - [ ] Real-time RSVP tracking in PostgreSQL.

## Phase 3: The Proactive Watchdog (Agents)
- [ ] **Event Scraper:** LangChain tools to monitor favorite wineries for music/specials.
- [ ] **Smart Notifications:** **Claude** filters events to find the "perfect match" for the user's personality.
- [ ] **Future Recommendations:** **Claude** analyzes long-term trends in the user's log to suggest new wine regions (e.g., "You love high-altitude Malbecs; let's plan a trip to Mendoza").

## Phase 4: Refinement & Scale
- [ ] **Offline Mode:** Local caching in Flutter for low-signal vineyard areas.
- [ ] **Social Feed:** Real-time updates on friend activity.
- [ ] **Wine Club Integration:** Automated sign-up for winery newsletters via Claude-generated forms.