import 'package:flutter/material.dart';

import '../models/help_article.dart';

const allHelpArticles = <HelpArticle>[
  // ══════════════════════════════════════════════════════════════
  // GETTING STARTED
  // ══════════════════════════════════════════════════════════════
  HelpArticle(
    id: 'getting-started-overview',
    title: 'Welcome to Trip Me',
    category: HelpCategory.gettingStarted,
    icon: Icons.waving_hand,
    keywords: ['welcome', 'overview', 'intro', 'about', 'what', 'trip me'],
    relatedRoutePrefix: '/dashboard',
    sections: [
      HelpSection(
        body:
            'Trip Me helps you plan wine, brewery, and restaurant trips with AI-powered assistance. '
            'Check in at stops, log drinks, rate experiences, get personalized recommendations, '
            'and build a history of your tasting adventures.',
      ),
      HelpSection(
        heading: 'Key Features',
        body:
            'Plan trips manually or with Sippy AI. '
            'Check in at stops, log drinks with photos and ratings. '
            'Get AI-powered recommendations, food pairings, and tasting flights. '
            'Track your wishlist, cellar, palate profile, and achievements. '
            'View your journey on an interactive map.',
      ),
      HelpSection(
        heading: 'Navigation',
        body:
            'Use the bottom navigation bar for main sections: Home, Explore, Trips, Visits, and Profile. '
            'Use the hamburger menu (top-left) for quick access to your Profile, Wishlist, Cellar, Palate, '
            'Achievements, Journey Map, and Help.',
        tipText: 'Tap the "?" icon on any screen for context-specific help.',
      ),
    ],
  ),

  HelpArticle(
    id: 'getting-started-first-trip',
    title: 'Planning Your First Trip',
    category: HelpCategory.gettingStarted,
    icon: Icons.assistant,
    keywords: ['first', 'trip', 'plan', 'start', 'begin', 'new', 'sippy'],
    relatedRoutePrefix: '/trips',
    sections: [
      HelpSection(
        heading: 'Option 1: Plan with Sippy AI',
        body:
            'On the Trips screen, tap the "Sippy" button. Tell Sippy where you want to go, '
            'when, and what you like. Sippy will ask a few quick questions, search for places, '
            'and build a complete trip with stops, times, and drive distances. '
            'Review the preview and tap "Looks Good!" to create it.',
        stepIcon: Icons.auto_awesome,
      ),
      HelpSection(
        heading: 'Option 2: Create Manually',
        body:
            'Tap the "+" button on the Trips screen. Give your trip a name and date. '
            'Then add stops by searching for places.',
        stepIcon: Icons.add_circle,
      ),
      HelpSection(
        heading: 'Starting Your Trip',
        body:
            'Trips automatically activate on the scheduled date and time. '
            'You can also start a trip manually from the trip detail screen. '
            'Once active, navigate between stops, check in, and log your experience.',
        stepIcon: Icons.play_circle,
      ),
      HelpSection(
        heading: 'Completing Your Trip',
        body:
            'At your last stop, tap "Complete Trip". '
            'For completed trips, you can view a Trip Recap with all your stops, wines, ratings, and photos.',
        stepIcon: Icons.celebration,
      ),
    ],
  ),

  HelpArticle(
    id: 'getting-started-navigation',
    title: 'Getting Around the App',
    category: HelpCategory.gettingStarted,
    icon: Icons.navigation,
    keywords: ['navigate', 'tabs', 'menu', 'bottom', 'bar', 'drawer', 'hamburger'],
    sections: [
      HelpSection(
        heading: 'Bottom Navigation',
        body:
            'Home — dashboard with stats, active trips, recent visits.\n'
            'Explore — search and browse places on a map.\n'
            'Trips — your trips list, create new or plan with Sippy.\n'
            'Visits — your check-in history.\n'
            'Profile — your account, stats, and settings.',
      ),
      HelpSection(
        heading: 'Main Menu (Hamburger)',
        body:
            'Tap the hamburger icon (top-left on main screens) to access:\n'
            'Profile, Journey Map, My Wishlist, My Cellar, My Palate, '
            'Achievements, Help & Guide, and Log Out.',
      ),
      HelpSection(
        heading: 'Trip Navigation Drawer',
        body:
            'Inside a trip or stop, tap the menu icon (top-right) to open the trip drawer. '
            'Jump to any stop, view the full route, trip recap, group palate match, '
            'or edit/delete the trip or stop.',
      ),
    ],
  ),

  // ══════════════════════════════════════════════════════════════
  // SIPPY AI
  // ══════════════════════════════════════════════════════════════
  HelpArticle(
    id: 'sippy-planner',
    title: 'Plan with Sippy',
    category: HelpCategory.sippy,
    icon: Icons.auto_awesome,
    keywords: ['sippy', 'plan', 'ai', 'trip', 'planner', 'create', 'suggest'],
    relatedRoutePrefix: '/trips',
    sections: [
      HelpSection(
        body:
            'Sippy is your AI trip planning assistant. Tap the "Sippy" button on the Trips screen '
            'to start a planning conversation.',
      ),
      HelpSection(
        heading: 'How It Works',
        body:
            '1. Tell Sippy where, when, and what you like.\n'
            '2. Sippy asks a few follow-up questions (one at a time).\n'
            '3. Sippy searches for real places and builds an itinerary.\n'
            '4. Review the trip preview with stops, times, and a route map.\n'
            '5. Tap "Looks Good!" to create the trip, or type changes.',
      ),
      HelpSection(
        heading: 'Tips for Better Results',
        body:
            'Include as much detail as possible in your first message: location, date, '
            'start time, how long at each stop, max drive time, and what you like to drink. '
            'Tap "Use as template" on the example prompt to get started quickly.',
      ),
      HelpSection(
        heading: 'Conversation History',
        body:
            'Sippy conversations are saved automatically. Long-press the Sippy button '
            'or tap the history icon in the chat header to see past conversations.',
      ),
    ],
  ),

  HelpArticle(
    id: 'sippy-ask',
    title: 'Ask Sippy',
    category: HelpCategory.sippy,
    icon: Icons.chat,
    keywords: ['sippy', 'ask', 'chat', 'question', 'recommend', 'help', 'trip'],
    relatedRoutePrefix: '/trips',
    sections: [
      HelpSection(
        body:
            'When viewing a trip or stop, tap the "Sippy" button (bottom-right) to chat with Sippy '
            'about that specific trip.',
      ),
      HelpSection(
        heading: 'What You Can Ask',
        body:
            'What should I order at this stop?\n'
            'Best order to visit the stops?\n'
            'Wine pairing suggestions for dinner.\n'
            'How long is the drive between stops?\n'
            'Any must-try wines on the menu?',
      ),
      HelpSection(
        body:
            'Sippy knows your trip details, all stops, menus, members, your palate profile, '
            'and your past visits. Answers are personalized to you.',
      ),
    ],
  ),

  HelpArticle(
    id: 'sippy-recommendations',
    title: 'AI Recommendations & Pairings',
    category: HelpCategory.sippy,
    icon: Icons.restaurant_menu,
    keywords: ['recommend', 'pairing', 'food', 'wine', 'flight', 'suggest', 'ai'],
    relatedRoutePrefix: '/trips',
    sections: [
      HelpSection(
        body:
            'After checking in at a stop that has a drink menu, three AI-powered tools appear:',
      ),
      HelpSection(
        heading: 'Get Recommendations',
        body:
            'AI picks the top 3 drinks from the menu based on your palate profile and past ratings. '
            'Tap any recommendation to add it as a drink.',
      ),
      HelpSection(
        heading: 'Get Food Pairings',
        body:
            'At wineries/breweries: suggests food to pair with the drinks. '
            'At restaurants: suggests wines/beers to pair with the food. '
            'Each pairing includes why it works and a serving tip.',
      ),
      HelpSection(
        heading: 'Build Tasting Flight',
        body:
            'AI builds a curated 4-drink tasting flight from the menu:\n'
            'Opener (light/approachable) → Comfort (your style) → Stretch (something new) → Finisher (bold/memorable). '
            'Each drink gets a role badge and tasting guidance.',
      ),
      HelpSection(
        tipText:
            'All three features save their results — they persist when you navigate away and return.',
      ),
    ],
  ),

  HelpArticle(
    id: 'sippy-label-scanner',
    title: 'Wine Label Scanner',
    category: HelpCategory.sippy,
    icon: Icons.document_scanner,
    keywords: ['scan', 'label', 'camera', 'wine', 'recognize', 'photo', 'ai'],
    relatedRoutePrefix: '/trips',
    sections: [
      HelpSection(
        body:
            'When adding a drink, tap "Scan Label with AI" at the top of the form. '
            'Point your camera at a wine or beer label and the AI will extract the name, '
            'varietal, vintage, and description automatically.',
      ),
      HelpSection(
        tipText: 'Works best with clear, well-lit labels. The photo is also saved as the drink photo.',
      ),
    ],
  ),

  // ══════════════════════════════════════════════════════════════
  // DASHBOARD
  // ══════════════════════════════════════════════════════════════
  HelpArticle(
    id: 'dashboard-overview',
    title: 'Your Dashboard',
    category: HelpCategory.dashboard,
    icon: Icons.dashboard,
    keywords: ['dashboard', 'home', 'stats', 'overview', 'active'],
    relatedRoutePrefix: '/dashboard',
    sections: [
      HelpSection(
        heading: 'Stats',
        body:
            'Colored badges show your totals: Trips, Visits, unique Places, and Average Rating.',
      ),
      HelpSection(
        heading: 'Active Trips',
        body:
            'Carousel of your current trips (not completed or cancelled). '
            'Trips automatically activate on their scheduled date and time.',
      ),
      HelpSection(
        heading: 'Recent Visits & Discover',
        body:
            'Recent Visits shows your latest 5 check-ins. '
            'Discover suggests places you have not visited yet.',
      ),
    ],
  ),

  // ══════════════════════════════════════════════════════════════
  // TRIPS
  // ══════════════════════════════════════════════════════════════
  HelpArticle(
    id: 'trips-overview',
    title: 'Managing Your Trips',
    category: HelpCategory.trips,
    icon: Icons.map,
    keywords: ['trips', 'list', 'manage', 'filter', 'status', 'create'],
    relatedRoutePrefix: '/trips',
    sections: [
      HelpSection(
        body:
            'The Trips screen lists all your trips. Search by name and filter by status.',
      ),
      HelpSection(
        heading: 'Creating a Trip',
        body:
            'Two ways to create a trip:\n'
            '1. Tap "Sippy" to plan with AI assistance.\n'
            '2. Tap "+" to create manually with a name and date.',
      ),
      HelpSection(
        heading: 'Auto-Activation',
        body:
            'Trips with a scheduled date automatically move to "In Progress" when the date '
            'and meeting time arrive. No need to manually start them.',
      ),
      HelpSection(
        heading: 'Trip Statuses',
        body:
            'Draft → Planning → Confirmed → In Progress → Completed.\n'
            'Cancelled trips are hidden from the active list.',
      ),
    ],
  ),

  HelpArticle(
    id: 'trips-detail',
    title: 'Trip Details & Drawer',
    category: HelpCategory.trips,
    icon: Icons.info,
    keywords: ['trip', 'detail', 'edit', 'delete', 'drawer', 'menu', 'route', 'recap'],
    relatedRoutePrefix: '/trips',
    sections: [
      HelpSection(
        body:
            'The trip detail screen shows your trip with a hero image, dates, stops carousel, and members.',
      ),
      HelpSection(
        heading: 'Trip Drawer Menu',
        body:
            'Tap the menu icon (top-right) to open the slide-out drawer with:\n'
            'Trip Details — Overview, Recap, Show Full Route, Group Palate Match.\n'
            'Stops — jump to any stop directly.\n'
            'Manage — Edit Trip, Delete Trip.',
      ),
      HelpSection(
        heading: 'Trip Recap',
        body:
            'Available for completed trips. Shows a timeline of all stops visited, '
            'wines tasted, ratings, photos, travel stats, and members. Shareable.',
      ),
      HelpSection(
        heading: 'Group Palate Match',
        body:
            'For trips with 2+ members. AI analyzes everyone\'s palate profiles '
            'and recommends wines/styles the whole group will enjoy.',
      ),
    ],
  ),

  HelpArticle(
    id: 'trips-live',
    title: 'Live Trip Mode',
    category: HelpCategory.trips,
    icon: Icons.play_circle,
    keywords: ['live', 'trip', 'progress', 'navigate', 'stop', 'prev', 'next'],
    relatedRoutePrefix: '/trips',
    sections: [
      HelpSection(
        body:
            'During an active trip, navigate between stops using the Previous/Next buttons at the bottom, '
            'or jump to any stop via the trip drawer (menu icon).',
      ),
      HelpSection(
        heading: 'At Each Stop',
        body:
            'Check in to unlock: drink menu, AI recommendations, food pairings, tasting flights, '
            'drink logging, ratings, notes, and the activity feed.',
      ),
      HelpSection(
        heading: 'Activity Feed',
        body:
            'See what other trip members are doing in real-time: check-ins, wines tasted, ratings.',
      ),
      HelpSection(
        heading: 'Completing the Trip',
        body:
            'At the last stop, tap "Complete Trip" to finish. View the Trip Recap afterward.',
      ),
    ],
  ),

  // ══════════════════════════════════════════════════════════════
  // STOPS & CHECK-IN
  // ══════════════════════════════════════════════════════════════
  HelpArticle(
    id: 'stops-overview',
    title: 'At a Stop',
    category: HelpCategory.stops,
    icon: Icons.place,
    keywords: ['stop', 'detail', 'check', 'in', 'map', 'menu', 'favorite'],
    relatedRoutePrefix: '/trips',
    sections: [
      HelpSection(
        body:
            'Each stop shows the place photo, map, address, phone, website, and drink menu.',
      ),
      HelpSection(
        heading: 'Checking In',
        body:
            'Tap "Check In" to record your arrival. This unlocks AI tools (recommendations, '
            'pairings, flights), drink logging, ratings, notes, and the activity feed.',
      ),
      HelpSection(
        heading: 'Wishlist Notifications',
        body:
            'When you check in, the app checks if any drinks on your wishlist are on the menu. '
            'If found, you get a notification!',
      ),
      HelpSection(
        heading: 'Drink Menu',
        body:
            'Browse the drink menu (fetched from the place\'s website). '
            'Tap the bookmark icon on any item to add it to your wishlist. '
            'Tap an item to log it as a drink.',
      ),
      HelpSection(
        heading: 'Undo Check-In',
        body:
            'Tap the green "Checked In" badge to undo. '
            'This clears all drinks, ratings, and notes for that stop.',
      ),
    ],
  ),

  // ══════════════════════════════════════════════════════════════
  // DRINKS
  // ══════════════════════════════════════════════════════════════
  HelpArticle(
    id: 'drinks-add',
    title: 'Logging Drinks',
    category: HelpCategory.drinks,
    icon: Icons.local_drink,
    keywords: ['drink', 'wine', 'beer', 'log', 'add', 'taste', 'tasting', 'scan'],
    relatedRoutePrefix: '/trips',
    sections: [
      HelpSection(
        body: 'After checking in, add drinks from the menu or manually:',
      ),
      HelpSection(
        heading: 'From the Menu',
        body: 'Tap any item in the drink menu scroll to pre-fill the form.',
      ),
      HelpSection(
        heading: 'Scan a Label',
        body:
            'Tap "Scan Label with AI" at the top of the drink form. '
            'Point your camera at the label to auto-fill name, varietal, and vintage.',
      ),
      HelpSection(
        heading: 'What You Can Log',
        body:
            'Name, type (varietal), serving size, tasting notes, rating (1-5 stars), '
            'rating comments, photo, favorite toggle, and purchase tracking (price + quantity).',
      ),
      HelpSection(
        heading: 'Wishlist',
        body:
            'Tap "Add to Wishlist" in the drink form to save a wine for later. '
            'You can also bookmark drinks directly from the drink menu.',
      ),
    ],
  ),

  // ══════════════════════════════════════════════════════════════
  // VISITS
  // ══════════════════════════════════════════════════════════════
  HelpArticle(
    id: 'visits-overview',
    title: 'Your Visit History',
    category: HelpCategory.visits,
    icon: Icons.history,
    keywords: ['visit', 'history', 'list', 'sort', 'detail'],
    relatedRoutePrefix: '/visits',
    sections: [
      HelpSection(
        body:
            'The Visits screen shows every place you have checked into. '
            'Sort by date or rating, group by place, or search by name.',
      ),
      HelpSection(
        heading: 'Visit Details',
        body:
            'Tap a visit to see the full detail page with: place photo header, '
            'quick stats (tastings, rating, favorites, purchases), '
            'experience rating bars, notes, photo gallery, and all drinks tasted with '
            'type badges, ratings, and tasting notes.',
      ),
    ],
  ),

  // ══════════════════════════════════════════════════════════════
  // EXPLORE
  // ══════════════════════════════════════════════════════════════
  HelpArticle(
    id: 'explore-overview',
    title: 'Exploring Places',
    category: HelpCategory.explore,
    icon: Icons.explore,
    keywords: ['explore', 'browse', 'search', 'map', 'places', 'favorite'],
    relatedRoutePrefix: '/explore',
    sections: [
      HelpSection(
        body:
            'Three tabs: Places (list), Map, and Favorites. '
            'Search by name or city. Tap any place for full details.',
      ),
      HelpSection(
        heading: 'Map',
        body:
            'Interactive map with color-coded markers (purple=winery, orange=brewery, green=restaurant). '
            'Pan and zoom to explore. Nearby places load automatically.',
      ),
      HelpSection(
        heading: 'Favorites',
        body:
            'Tap the heart icon on any place to favorite it. '
            'View all favorites in the Favorites tab.',
      ),
      HelpSection(
        heading: 'Start a Trip',
        body:
            'From any place detail, tap "Start Trip" to create a new trip with that place as the first stop.',
      ),
    ],
  ),

  // ══════════════════════════════════════════════════════════════
  // PROFILE & TOOLS
  // ══════════════════════════════════════════════════════════════
  HelpArticle(
    id: 'profile-overview',
    title: 'Your Profile',
    category: HelpCategory.profile,
    icon: Icons.person,
    keywords: ['profile', 'account', 'stats', 'menu', 'drawer'],
    relatedRoutePrefix: '/profile',
    sections: [
      HelpSection(
        body:
            'Your profile shows your avatar, name, email, subscription status, and activity stats.',
      ),
      HelpSection(
        heading: 'Quick Access (Main Menu)',
        body:
            'Tap the hamburger icon (top-left) on any main screen for:\n'
            'Profile, Journey Map, My Wishlist, My Cellar, My Palate, '
            'Achievements, Help & Guide, and Log Out.',
      ),
    ],
  ),

  HelpArticle(
    id: 'profile-palate',
    title: 'My Palate',
    category: HelpCategory.profile,
    icon: Icons.insights,
    keywords: ['palate', 'taste', 'preference', 'analyze', 'sippy', 'ai'],
    relatedRoutePrefix: '/profile/palate',
    sections: [
      HelpSection(
        body:
            'Your AI-generated taste profile based on your tasting history.',
      ),
      HelpSection(
        heading: 'Analyze My Palate',
        body:
            'Tap "Analyze My Palate with AI" to have Claude analyze your ratings, '
            'wines, and notes. Get a summary of your preferences (sweetness, body, acidity, '
            'tannins), favorite styles, and personalized recommendations.',
      ),
      HelpSection(
        heading: 'Ask Sippy',
        body:
            'Tap the "Ask Sippy" button to chat about wine, beer, what to try next, '
            'or any tasting questions based on your history.',
      ),
    ],
  ),

  HelpArticle(
    id: 'profile-wishlist',
    title: 'My Wishlist',
    category: HelpCategory.profile,
    icon: Icons.bookmark,
    keywords: ['wishlist', 'want', 'try', 'bookmark', 'save', 'later'],
    relatedRoutePrefix: '/profile/wishlist',
    sections: [
      HelpSection(
        body:
            'Your list of drinks to try later. Add drinks from the drink menu (bookmark icon) '
            'or from the drink form ("Add to Wishlist").',
      ),
      HelpSection(
        heading: 'Wishlist Alerts',
        body:
            'When you check in at a stop, the app checks if any wishlisted drinks '
            'are on that place\'s menu. If found, you get a notification!',
      ),
      HelpSection(
        body: 'Access from: Main Menu → My Wishlist, or Profile → My Wishlist.',
      ),
    ],
  ),

  HelpArticle(
    id: 'profile-cellar',
    title: 'My Cellar',
    category: HelpCategory.profile,
    icon: Icons.inventory_2,
    keywords: ['cellar', 'purchase', 'bought', 'bottle', 'spend', 'collection'],
    relatedRoutePrefix: '/profile/cellar',
    sections: [
      HelpSection(
        body:
            'Dashboard of drinks you have purchased. Shows total bottles, total spend, '
            'average price, top places by spend, favorite varietals, and recent purchases.',
      ),
      HelpSection(
        body:
            'Purchases are tracked when you toggle "Bought a bottle?" in the drink form '
            'and enter the price and quantity.',
      ),
    ],
  ),

  HelpArticle(
    id: 'profile-badges',
    title: 'Achievements',
    category: HelpCategory.profile,
    icon: Icons.emoji_events,
    keywords: ['badge', 'achievement', 'milestone', 'reward', 'progress'],
    relatedRoutePrefix: '/profile/badges',
    sections: [
      HelpSection(
        body:
            '24 wine-themed badges across 6 categories: Explorer, Wine & Beer, Trips, '
            'Sippy & AI, Ratings, and Purchases.',
      ),
      HelpSection(
        heading: 'Examples',
        body:
            'First Sip — your first check-in.\n'
            'Connoisseur — log 50 wines.\n'
            'Road Tripper — complete your first trip.\n'
            'Sippy\'s Friend — plan a trip with AI.\n'
            'Take-Home — buy your first bottle.',
      ),
      HelpSection(
        body: 'Tap any badge to see its description and your progress toward earning it.',
      ),
    ],
  ),

  HelpArticle(
    id: 'profile-journey-map',
    title: 'Journey Map',
    category: HelpCategory.profile,
    icon: Icons.map,
    keywords: ['journey', 'map', 'history', 'visited', 'places', 'marker'],
    relatedRoutePrefix: '/profile/history',
    sections: [
      HelpSection(
        body:
            'An interactive map showing every place you have visited. '
            'Color-coded markers by place type.',
      ),
      HelpSection(
        heading: 'Place Cards',
        body:
            'Tap any marker to see a card with: place photo, name, address, website, phone, '
            'visit count, last visit date. Tap "Last Visit" to see the visit detail, '
            'or "Start Trip" to create a new trip from that place.',
      ),
      HelpSection(
        body: 'Access from: Main Menu → Journey Map.',
      ),
    ],
  ),

  HelpArticle(
    id: 'profile-subscription',
    title: 'Subscription & Billing',
    category: HelpCategory.profile,
    icon: Icons.credit_card,
    keywords: ['subscription', 'billing', 'payment', 'plan', 'trial'],
    relatedRoutePrefix: '/profile/subscription',
    sections: [
      HelpSection(
        body:
            'View your subscription status, trial period, and billing details. '
            'Manage your subscription through the customer portal.',
      ),
    ],
  ),
];
