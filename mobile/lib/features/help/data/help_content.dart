import 'package:flutter/material.dart';

import '../models/help_article.dart';

const allHelpArticles = <HelpArticle>[
  // ══════════════════════════════════════════════════════════════
  // GETTING STARTED
  // ══════════════════════════════════════════════════════════════
  HelpArticle(
    id: 'getting-started-overview',
    title: 'Welcome to Vino',
    category: HelpCategory.gettingStarted,
    icon: Icons.waving_hand,
    keywords: ['welcome', 'overview', 'intro', 'about', 'what'],
    relatedRoutePrefix: '/dashboard',
    sections: [
      HelpSection(
        body:
            'Vino helps you plan wine and brewery trips, check in at stops along the way, '
            'log the drinks you taste, rate your experiences, and build a history of your visits.',
      ),
      HelpSection(
        heading: 'What You Can Do',
        body:
            'Plan trips with multiple stops at wineries, breweries, and restaurants. '
            'Check in when you arrive, browse the drink menu, log what you taste with photos and ratings, '
            'and look back at your visit history anytime.',
      ),
      HelpSection(
        heading: 'Navigation',
        body:
            'Use the bottom navigation bar to move between the main sections of the app: '
            'Home (Dashboard), Explore, Trips, Visits, and Profile.',
        tipText: 'Tap the "?" icon in the top-right of any screen for help specific to that page.',
      ),
    ],
  ),

  HelpArticle(
    id: 'getting-started-first-trip',
    title: 'Planning Your First Trip',
    category: HelpCategory.gettingStarted,
    icon: Icons.assistant,
    keywords: ['first', 'trip', 'plan', 'start', 'begin', 'new'],
    relatedRoutePrefix: '/trips',
    sections: [
      HelpSection(
        heading: 'Step 1: Create a Trip',
        body:
            'Go to the Trips tab and tap the "+" button. Give your trip a name, optional description, '
            'and set a date. Tap "Create" to get started.',
        stepIcon: Icons.add_circle,
      ),
      HelpSection(
        heading: 'Step 2: Add Stops',
        body:
            'From your trip details, tap "Add Stop". Search for wineries, breweries, or restaurants '
            'by name or location. Tap a marker on the map or a result in the list, then tap "Add to Trip".',
        stepIcon: Icons.add_location,
      ),
      HelpSection(
        heading: 'Step 3: Start Your Trip',
        body:
            'When you are ready, tap "Start Trip" to enter live mode. '
            'Navigate between stops, check in when you arrive, and log your drinks and ratings.',
        stepIcon: Icons.play_circle,
      ),
      HelpSection(
        heading: 'Step 4: Complete Your Trip',
        body:
            'After your last stop, tap "Complete Trip" to finish. '
            'Your visits, drinks, and ratings are saved to your history.',
        stepIcon: Icons.celebration,
      ),
    ],
  ),

  HelpArticle(
    id: 'getting-started-navigation',
    title: 'Getting Around the App',
    category: HelpCategory.gettingStarted,
    icon: Icons.navigation,
    keywords: ['navigate', 'tabs', 'menu', 'bottom', 'bar', 'screens'],
    sections: [
      HelpSection(
        heading: 'Home',
        body:
            'Your dashboard with stats (trips, visits, places, average rating), '
            'active trips, recent visits, top-rated places, and new places to discover.',
        stepIcon: Icons.dashboard,
      ),
      HelpSection(
        heading: 'Explore',
        body:
            'Search and browse wineries, breweries, and restaurants. '
            'View them on a map, see details, and add them to your favorites.',
        stepIcon: Icons.explore,
      ),
      HelpSection(
        heading: 'Trips',
        body:
            'View, create, and manage your trips. '
            'Each trip has stops you can plan, reorder, and visit in live mode.',
        stepIcon: Icons.map,
      ),
      HelpSection(
        heading: 'Visits',
        body:
            'Your visit history. See all the places you have checked into, '
            'sorted by date or grouped by place. View ratings and drinks from each visit.',
        stepIcon: Icons.history,
      ),
      HelpSection(
        heading: 'Profile',
        body:
            'View your stats, manage your palate profile, subscription, and app settings.',
        stepIcon: Icons.person,
      ),
    ],
  ),

  HelpArticle(
    id: 'getting-started-checkin',
    title: 'Your First Check-In',
    category: HelpCategory.gettingStarted,
    icon: Icons.check_circle,
    keywords: ['check', 'in', 'checkin', 'arrive', 'first', 'visit'],
    relatedRoutePrefix: '/trips',
    sections: [
      HelpSection(
        body:
            'When you arrive at a stop during a live trip, open the stop details and tap the "Check In" button. '
            'This creates a visit record and unlocks the ability to log drinks, rate your experience, and add notes.',
      ),
      HelpSection(
        heading: 'After Checking In',
        body:
            'Once checked in, you will see new sections appear: My Drinks, Rate Experience, and Stop Notes. '
            'The "Checked In" badge appears in the header — you can tap it to undo your check-in if needed.',
      ),
      HelpSection(
        tipText:
            'You can undo a check-in by tapping the green "Checked In" badge. '
            'This will clear all drinks, ratings, and notes for that stop so you can start fresh.',
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
    keywords: ['dashboard', 'home', 'stats', 'badges', 'overview'],
    relatedRoutePrefix: '/dashboard',
    sections: [
      HelpSection(
        heading: 'Stats Badges',
        body:
            'The colored badges at the top show your key stats: total Trips, '
            'Visits, unique Places visited, and your Average Rating across all visits.',
      ),
      HelpSection(
        heading: 'Active Trips',
        body:
            'The carousel shows your current trips that are not yet completed or cancelled. '
            'Tap a trip card to open it. Cards show the trip name, dates, member and stop counts, '
            'and a cover image from the first stop.',
      ),
      HelpSection(
        heading: 'Recent Visits',
        body:
            'Your latest 5 visits, showing the place name, date, wine count, and overall rating. '
            'Tap any visit to see its full details.',
      ),
      HelpSection(
        heading: 'Top Places & Discover',
        body:
            'Top Places shows your highest-rated venues. '
            'Discover suggests places you have not visited yet, based on overall ratings.',
      ),
    ],
  ),

  HelpArticle(
    id: 'dashboard-discover',
    title: 'Discovering New Places',
    category: HelpCategory.dashboard,
    icon: Icons.auto_awesome,
    keywords: ['discover', 'new', 'places', 'recommendations', 'suggest'],
    relatedRoutePrefix: '/dashboard',
    sections: [
      HelpSection(
        body:
            'The Discover section on your dashboard shows places you have not visited yet, '
            'ranked by their average rating from all users.',
      ),
      HelpSection(
        body:
            'Tap any place card to see its full details — address, website, phone, and menu items. '
            'From the place details, you can add it to your favorites or start a new trip.',
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
    keywords: ['trips', 'list', 'manage', 'filter', 'status'],
    relatedRoutePrefix: '/trips',
    sections: [
      HelpSection(
        body:
            'The Trips screen lists all your trips. Use the search bar to find trips by name. '
            'Trips are organized by status: Draft, Planning, Confirmed, In Progress, Completed, and Cancelled.',
      ),
      HelpSection(
        heading: 'Trip Statuses',
        body:
            'Draft — just created, not yet planned.\n'
            'Planning — adding stops and details.\n'
            'Confirmed — ready to go, date set.\n'
            'In Progress — currently on the trip.\n'
            'Completed — trip is finished.\n'
            'Cancelled — trip was cancelled.',
      ),
      HelpSection(
        heading: 'Creating a Trip',
        body:
            'Tap the "+" button to create a new trip. You can also start a trip directly from the Explore tab '
            'by finding a place and choosing "Start a Trip".',
      ),
    ],
  ),

  HelpArticle(
    id: 'trips-create',
    title: 'Creating a Trip',
    category: HelpCategory.trips,
    icon: Icons.add_circle,
    keywords: ['create', 'new', 'trip', 'plan', 'name', 'date'],
    relatedRoutePrefix: '/trips',
    sections: [
      HelpSection(
        body:
            'To create a trip, tap the "+" button on the Trips screen. Fill in a trip name '
            'and optionally a description, scheduled date, end date, and meeting point.',
      ),
      HelpSection(
        heading: 'Adding Stops',
        body:
            'After creating the trip, open it and tap "Add Stop" to search for places. '
            'You can search by name, city, or browse the map. Filter by type: Wineries, Breweries, or Restaurants.',
      ),
      HelpSection(
        tipText:
            'You can drag and drop stops to reorder them. The order determines the suggested route for your trip.',
      ),
    ],
  ),

  HelpArticle(
    id: 'trips-detail',
    title: 'Trip Details',
    category: HelpCategory.trips,
    icon: Icons.info,
    keywords: ['trip', 'detail', 'edit', 'delete', 'members', 'stops', 'info'],
    relatedRoutePrefix: '/trips',
    sections: [
      HelpSection(
        body:
            'The trip detail screen shows your trip name, dates, status, member count, and all planned stops. '
            'A cover image is pulled from the first stop that has one.',
      ),
      HelpSection(
        heading: 'Editing & Deleting',
        body:
            'Tap the pencil icon in the header to edit the trip name, description, dates, and meeting point. '
            'Tap the trash icon to delete the trip (you will be asked to confirm).',
      ),
      HelpSection(
        heading: 'Managing Stops',
        body:
            'Stops are listed in order below the trip info. Tap a stop to see its details. '
            'Drag the handle on the right to reorder stops. '
            'Tap "Add Stop" to search and add new places.',
      ),
      HelpSection(
        heading: 'Starting Live Mode',
        body:
            'When your trip is confirmed and the date has arrived, tap "Start Trip" to enter live mode. '
            'This changes the trip status to In Progress and lets you check in at each stop.',
      ),
    ],
  ),

  HelpArticle(
    id: 'trips-live',
    title: 'Live Trip Mode',
    category: HelpCategory.trips,
    icon: Icons.play_circle,
    keywords: ['live', 'trip', 'progress', 'active', 'start', 'go'],
    relatedRoutePrefix: '/trips',
    sections: [
      HelpSection(
        body:
            'Live mode activates when you start a trip. You will see a progress bar at the top '
            'showing how many stops you have visited.',
      ),
      HelpSection(
        heading: 'Navigating Stops',
        body:
            'Use the Previous and Next buttons at the bottom of each stop to move between them. '
            'The stop order matches what you planned in the trip details.',
      ),
      HelpSection(
        heading: 'Completing the Trip',
        body:
            'At your last stop, after checking in, a "Complete Trip" button appears. '
            'Tap it to mark the trip as completed. All your visits and drinks are saved.',
      ),
    ],
  ),

  HelpArticle(
    id: 'trips-stops',
    title: 'Adding & Managing Stops',
    category: HelpCategory.trips,
    icon: Icons.add_location,
    keywords: ['stop', 'add', 'remove', 'reorder', 'drag', 'search', 'map'],
    relatedRoutePrefix: '/trips',
    sections: [
      HelpSection(
        heading: 'Adding a Stop',
        body:
            'From the trip detail screen, tap "Add Stop". You can search by name or city, '
            'or browse the map. Filter by place type: Wineries, Breweries, or Restaurants. '
            'Tap a result and then "Add to Trip".',
      ),
      HelpSection(
        heading: 'The Add Stop Map',
        body:
            'The map starts centered on Charlotte, NC. Pan the map to search a different area — '
            'nearby places will load automatically. Tap a marker to see place details.',
      ),
      HelpSection(
        heading: 'Reordering Stops',
        body:
            'On the trip detail screen, drag the handle icon on the right side of each stop card '
            'to rearrange the order. The order determines your route.',
      ),
      HelpSection(
        heading: 'Removing a Stop',
        body:
            'Open a stop and tap the trash icon in the header. Confirm the removal. '
            'This also removes any check-ins, drinks, and ratings for that stop.',
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
    keywords: ['stop', 'detail', 'map', 'address', 'phone', 'check', 'in', 'favorite'],
    relatedRoutePrefix: '/trips',
    sections: [
      HelpSection(
        body:
            'The stop detail screen shows the place name, address, phone, website, and a map. '
            'Tap the address to open it in Google Maps for directions.',
      ),
      HelpSection(
        heading: 'Checking In',
        body:
            'During a live trip, tap the "Check In" button to record your arrival. '
            'This unlocks My Drinks, Rate Experience, and Stop Notes sections.',
      ),
      HelpSection(
        heading: 'Favorites',
        body:
            'Tap the heart icon in the header to add or remove a place from your favorites. '
            'Favorites appear in the Explore tab under the Favorites section.',
      ),
      HelpSection(
        heading: 'Editing & Deleting',
        body:
            'Use the pencil icon to edit stop details and the trash icon to remove the stop from the trip.',
      ),
    ],
  ),

  HelpArticle(
    id: 'stops-drinks',
    title: 'Logging Your Drinks',
    category: HelpCategory.stops,
    icon: Icons.local_drink,
    keywords: ['drink', 'wine', 'beer', 'log', 'add', 'menu', 'taste', 'tasting'],
    relatedRoutePrefix: '/trips',
    sections: [
      HelpSection(
        body:
            'After checking in, the "My Drinks" section appears. You can add drinks two ways:',
      ),
      HelpSection(
        heading: 'From the Drink Menu',
        body:
            'If the place has a drink menu loaded, tap any item in the menu carousel to pre-fill '
            'the drink form with its name and varietal. '
            'The menu can be fetched from the place\'s website — tap "Fetch Drink Menu from Website".',
      ),
      HelpSection(
        heading: 'Manual Entry',
        body:
            'Tap "Add Drink" to manually enter a drink. Fill in the name, type (varietal), '
            'serving size, tasting notes, rating comments, and star rating. '
            'You can also take a photo, mark it as a favorite, or track if you purchased a bottle.',
      ),
      HelpSection(
        heading: 'Editing & Removing',
        body:
            'Tap a drink card to expand it and see full details. '
            'Use the Edit button to modify any field, or Remove to delete it.',
      ),
      HelpSection(
        tipText:
            'Tap the drink thumbnail image to view it full-screen with pinch-to-zoom.',
      ),
    ],
  ),

  HelpArticle(
    id: 'stops-ratings',
    title: 'Rating Your Experience',
    category: HelpCategory.stops,
    icon: Icons.star,
    keywords: ['rate', 'rating', 'star', 'staff', 'ambience', 'food', 'overall'],
    relatedRoutePrefix: '/trips',
    sections: [
      HelpSection(
        body:
            'After checking in, the "Rate Experience" section lets you rate four aspects '
            'of your visit on a 1-5 star scale:',
      ),
      HelpSection(
        heading: 'Rating Categories',
        body:
            'Overall — your general impression.\n'
            'Staff — friendliness and knowledge.\n'
            'Ambience — atmosphere and setting.\n'
            'Food & Drinks — quality of what was served.',
      ),
      HelpSection(
        body:
            'Ratings are saved automatically when you tap the stars. '
            'Your average rating across visits is shown on your dashboard.',
      ),
    ],
  ),

  HelpArticle(
    id: 'stops-notes',
    title: 'Adding Notes',
    category: HelpCategory.stops,
    icon: Icons.note,
    keywords: ['note', 'notes', 'text', 'write', 'comment', 'stop'],
    relatedRoutePrefix: '/trips',
    sections: [
      HelpSection(
        body:
            'After checking in, the "Stop Notes" section lets you write free-form notes about your visit. '
            'These are separate from drink-level tasting notes and rating comments.',
      ),
      HelpSection(
        tipText:
            'Use stop notes for things like parking tips, special events, or recommendations for next time.',
      ),
    ],
  ),

  // ══════════════════════════════════════════════════════════════
  // DRINKS
  // ══════════════════════════════════════════════════════════════
  HelpArticle(
    id: 'drinks-add',
    title: 'Adding a Drink',
    category: HelpCategory.drinks,
    icon: Icons.add_circle,
    keywords: ['add', 'drink', 'form', 'name', 'type', 'serving', 'rating', 'favorite', 'purchase'],
    relatedRoutePrefix: '/trips',
    sections: [
      HelpSection(
        body: 'The drink form lets you capture everything about what you tasted:',
      ),
      HelpSection(
        heading: 'Basic Info',
        body:
            'Drink Name (required) — the name of the wine or beer.\n'
            'Type — the varietal (e.g., Chardonnay, IPA). Options change based on whether the place is a winery or brewery.\n'
            'Serving — how it was served (tasting, glass, flight, pint, etc.).',
      ),
      HelpSection(
        heading: 'Notes & Rating',
        body:
            'Tasting Notes — describe the flavors, aromas, and mouthfeel.\n'
            'Rating Comments — what you liked or disliked.\n'
            'Rating — 1 to 5 stars.',
      ),
      HelpSection(
        heading: 'Photo, Favorite & Purchase',
        body:
            'Photo — take a picture with your camera or pick from your gallery.\n'
            'Favorite — mark drinks you love for easy reference later.\n'
            'Bought a bottle/to go — track purchases with price and quantity.',
      ),
    ],
  ),

  HelpArticle(
    id: 'drinks-photos',
    title: 'Drink Photos',
    category: HelpCategory.drinks,
    icon: Icons.camera_alt,
    keywords: ['photo', 'camera', 'gallery', 'image', 'picture', 'zoom'],
    relatedRoutePrefix: '/trips',
    sections: [
      HelpSection(
        body:
            'You can attach a photo to any drink. In the drink form, use the Camera button to take a new photo '
            'or the Gallery button to pick an existing one.',
      ),
      HelpSection(
        heading: 'Viewing Photos',
        body:
            'Photos appear as thumbnails on the drink card. '
            'Tap the thumbnail to open a full-screen view where you can pinch to zoom and pan.',
      ),
      HelpSection(
        heading: 'Removing a Photo',
        body:
            'In the drink form, tap the X button on the photo preview to remove it. '
            'Save the drink to confirm the removal.',
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
    keywords: ['visit', 'history', 'list', 'sort', 'group', 'place'],
    relatedRoutePrefix: '/visits',
    sections: [
      HelpSection(
        body:
            'The Visits screen shows every place you have checked into. '
            'By default, visits are grouped by place so you can see how many times you have been to each venue.',
      ),
      HelpSection(
        heading: 'Sorting',
        body:
            'Use the "Sort by" dropdown to change the order: Newest First, Oldest First, '
            'Highest Rated, or Lowest Rated.',
      ),
      HelpSection(
        heading: 'Grouping',
        body:
            'Toggle "Group by Place" to group visits under place headers with a visit count badge, '
            'or turn it off for a flat chronological list.',
      ),
      HelpSection(
        heading: 'Place Details',
        body:
            'Tap the info icon on any visit or place group header to go to the Place Details page. '
            'Tap the visit itself to see its full details with ratings and drinks.',
      ),
    ],
  ),

  HelpArticle(
    id: 'visits-checkin',
    title: 'Standalone Check-In',
    category: HelpCategory.visits,
    icon: Icons.add_location_alt,
    keywords: ['checkin', 'standalone', 'outside', 'trip', 'manual', 'walk-in'],
    relatedRoutePrefix: '/visits',
    sections: [
      HelpSection(
        body:
            'You can check in to a place without being on a trip. '
            'On the Visits screen, tap the "+" button to start a standalone check-in.',
      ),
      HelpSection(
        body:
            'Search for the place, select it, and add your ratings and notes. '
            'The visit will appear in your history just like a trip check-in.',
      ),
    ],
  ),

  HelpArticle(
    id: 'visits-detail',
    title: 'Visit Details',
    category: HelpCategory.visits,
    icon: Icons.visibility,
    keywords: ['visit', 'detail', 'ratings', 'wines', 'drinks', 'view'],
    relatedRoutePrefix: '/visits',
    sections: [
      HelpSection(
        body:
            'Tap any visit to see its full details: the place, visit date, your four ratings '
            '(Overall, Staff, Ambience, Food), any notes you wrote, and all the drinks you logged.',
      ),
      HelpSection(
        body:
            'Each drink shows its name, type, serving, rating, and any tasting notes or photos you added.',
      ),
    ],
  ),

  // ══════════════════════════════════════════════════════════════
  // EXPLORE
  // ══════════════════════════════════════════════════════════════
  HelpArticle(
    id: 'explore-list',
    title: 'Browsing Places',
    category: HelpCategory.explore,
    icon: Icons.list,
    keywords: ['explore', 'browse', 'list', 'search', 'places', 'find'],
    relatedRoutePrefix: '/explore',
    sections: [
      HelpSection(
        body:
            'The Explore screen has three tabs: Places (list), Map, and Favorites. '
            'Use the search bar to find places by name or city.',
      ),
      HelpSection(
        heading: 'Place Cards',
        body:
            'Each card shows the place name, type, location, visit count, and average rating. '
            'Tap a card to see full details including address, phone, website, and drink menu.',
      ),
      HelpSection(
        heading: 'From Place Details',
        body:
            'From a place detail page you can tap the heart to favorite it, '
            'view the address on a map, call the phone number, or visit the website.',
      ),
    ],
  ),

  HelpArticle(
    id: 'explore-map',
    title: 'Map View',
    category: HelpCategory.explore,
    icon: Icons.map,
    keywords: ['map', 'explore', 'marker', 'pin', 'search', 'nearby', 'location'],
    relatedRoutePrefix: '/explore',
    sections: [
      HelpSection(
        body:
            'The Map tab shows places as markers on an interactive map. '
            'Markers are color-coded: purple for wineries, orange for breweries, green for restaurants.',
      ),
      HelpSection(
        heading: 'Searching',
        body:
            'Type a name or city in the search bar and press enter. '
            'Results appear as markers on the map and in a list below.',
      ),
      HelpSection(
        heading: 'Browsing by Area',
        body:
            'Pan or zoom the map to explore different areas. '
            'When you stop moving, nearby places load automatically based on the visible area.',
      ),
    ],
  ),

  HelpArticle(
    id: 'explore-favorites',
    title: 'Your Favorites',
    category: HelpCategory.explore,
    icon: Icons.favorite,
    keywords: ['favorite', 'heart', 'save', 'like', 'bookmark'],
    relatedRoutePrefix: '/explore',
    sections: [
      HelpSection(
        body:
            'The Favorites tab in Explore shows all places you have hearted. '
            'Tap the heart icon on any place card or in the place detail header to toggle it.',
      ),
      HelpSection(
        body:
            'Favorites are a quick way to save places you want to visit later. '
            'You can create a trip from your favorites by going to a favorite place and adding it as a stop.',
      ),
    ],
  ),

  // ══════════════════════════════════════════════════════════════
  // PROFILE
  // ══════════════════════════════════════════════════════════════
  HelpArticle(
    id: 'profile-overview',
    title: 'Your Profile',
    category: HelpCategory.profile,
    icon: Icons.person,
    keywords: ['profile', 'account', 'stats', 'avatar', 'info'],
    relatedRoutePrefix: '/profile',
    sections: [
      HelpSection(
        body:
            'Your profile shows your avatar, name, email, and key stats '
            '(total visits, unique places, average rating).',
      ),
      HelpSection(
        heading: 'Menu Items',
        body:
            'My Palate — your taste preferences and palate profile.\n'
            'Subscription — manage your subscription status and billing.\n'
            'Help & Guide — the help system you are reading right now.',
      ),
    ],
  ),

  HelpArticle(
    id: 'profile-palate',
    title: 'My Palate',
    category: HelpCategory.profile,
    icon: Icons.insights,
    keywords: ['palate', 'taste', 'preference', 'profile', 'flavor'],
    relatedRoutePrefix: '/profile/palate',
    sections: [
      HelpSection(
        body:
            'The Palate Profile captures your drink preferences — the types of wines or beers '
            'you enjoy, flavor profiles you prefer, and your experience level.',
      ),
      HelpSection(
        body:
            'This information can be used to help recommend drinks and places that match your taste.',
      ),
    ],
  ),

  HelpArticle(
    id: 'profile-subscription',
    title: 'Subscription & Billing',
    category: HelpCategory.profile,
    icon: Icons.credit_card,
    keywords: ['subscription', 'billing', 'payment', 'plan', 'trial', 'upgrade'],
    relatedRoutePrefix: '/profile/subscription',
    sections: [
      HelpSection(
        body:
            'View your current subscription status, trial period, and billing details. '
            'Manage your subscription through the customer portal.',
      ),
    ],
  ),
];
