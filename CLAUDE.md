# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**reSchool** is an unofficial iOS client for the eSchool electronic diary system (app.eschool.center), written in Swift 5 using SwiftUI. The app provides native access to student schedules, grades, homework, messaging, and school directory features. A Python CLI version (`main.py`) is also included.

## Development Commands

### Build and Run
```bash
# Open project in Xcode
open reschool.xcodeproj

# Build from command line (after opening in Xcode)
xcodebuild -project reschool.xcodeproj -scheme reschool -configuration Debug build

# Run in simulator via Xcode: Cmd + R
```

### Python CLI Version
```bash
# Install dependencies
pip install requests rich

# Run CLI client
python3 main.py
```

### Utilities
```bash
# Clean project data (Python script)
python3 clean.py
```

## Architecture

### MVVM Pattern
The app follows **MVVM (Model-View-ViewModel)** architecture:

- **Models** (`Models.swift`): All API response structures and data models using `Codable`
- **Views** (`*View.swift`): SwiftUI views for each feature (Diary, Marks, Homework, Chats, Profile, SchoolDirectory)
- **Service Layer** (`APIService.swift`): Centralized API client acting as ViewModel, manages all network requests and authentication state

### Key Components

#### APIService (Singleton)
- **Location**: `APIService.swift`
- **Role**: Centralized API client using `ObservableObject` pattern
- **Key Responsibilities**:
  - Session management with cookie-based authentication (JSESSIONID)
  - All eSchool API endpoint interactions
  - User state tracking (`userId`, `currentPrsId`, `userProfile`)
  - Auto-login attempts using saved credentials
  - Request/response logging for debugging
- **Authentication Flow**: Login → Store session cookie in Keychain → Fetch user state → Set `isAuthenticated` flag
- **Device Spoofing**: Uses random Android device models from `Assets.xcassets/devices.dataset/devices.json` to mimic mobile app

#### KeychainHelper
- **Location**: `KeychainHelper.swift`
- **Role**: Secure storage wrapper for sensitive data
- **Stores**: Session cookies, saved credentials (username/password)
- **Service/Account naming**: Uses `"reschool-app"` service with specific account identifiers

#### Security
- **Password Hashing**: SHA256 hash computed client-side before transmission (`CryptoHelper.sha256()` in `Helpers.swift`)
- **Storage**: Keychain for credentials and session tokens, `@AppStorage` for user preferences
- **Device Info**: Randomized device model selection for API authentication

### View Structure

The main `ContentView.swift` conditionally shows either `LoginView` or a `TabView` with 7 tabs based on `APIService.shared.isAuthenticated`:

1. **DiaryView** - Weekly schedule with lessons, times, grades, homework indicators
2. **MarksView** - Grades by subject with period selection and average calculations
3. **HomeworkView** - Assignments with date filtering and file attachments
4. **ChatsView** - Full messaging interface (personal/group chats, user search, create groups)
5. **ProfileView** - Student info, class, year, parent/child relations
6. **SchoolDirectoryView** - Browse school structure, groups, staff
7. **AboutView** - App information

### Shared Components
- **Location**: `Components.swift`
- **AppColors**: Semantic color system using system dynamic colors
- **GlassCard**: Reusable card UI with material blur effect
- **GradeBadge**: Color-coded grade display (green ≥4.5, blue ≥3.5, orange ≥2.5, red <2.5)
- **GenericAsyncAvatar**: Avatar loader with fallback initials

### Helper Utilities
- **Location**: `Helpers.swift`
- **CryptoHelper**: SHA256 hashing, random string generation
- **Calendar.school**: Russian locale calendar with Monday as first weekday
- **String.strippingHTML()**: HTML tag removal for text display
- **Color(hex:)**: Hex color initialization

## Data Flow

1. **App Launch**: `reschoolApp.swift` → `ContentView` → Check `APIService.shared.isAuthenticated`
2. **Authentication**:
   - If session cookie exists: Attempt auto-login via `/state` endpoint
   - If saved credentials exist: Re-login automatically
   - Otherwise: Show `LoginView`
3. **API Requests**: Views call `APIService.shared` async methods → Parse JSON to `Models.swift` structs → Update SwiftUI views
4. **Session Persistence**: Session cookie saved to Keychain on successful login, loaded on app init

## API Endpoints

All endpoints use base URL: `https://app.eschool.center/ec-server`

Key endpoints (see `APIService.swift` for complete list):
- `/login` - Authentication (POST with form-encoded username/password hash)
- `/state` - Fetch current user state and profile
- `/student/getDiaryUnits` - Get grades by subject for period
- `/student/getPrsDiary` - Get schedule/diary for date range
- `/student/getLPartListPupil` - Get homework tasks
- `/chat/*` - Messaging endpoints (threads, messages, send, create groups)
- `/profile/getProfile_new` - Detailed user profile
- `/groups/tree` - School directory structure
- `/files/*` - File downloads (homework attachments, avatars)

## Settings and Configuration

User preferences stored via `@AppStorage`:
- `saved_device_model` - Randomly selected device identifier (persisted across launches)
- Settings accessible via `SettingsView.swift` (current year filter, homework date range)

## Requirements

- **Xcode**: 15.0+
- **iOS Deployment Target**: 17.0+
- **Language**: Swift 5
- **UI Framework**: SwiftUI
- **Async**: Swift Concurrency (async/await)

## Important Implementation Notes

### When Adding New Features
- API requests should go through `APIService.shared` methods
- Use `async/await` for all network operations
- Create corresponding `Codable` models in `Models.swift`
- Follow existing view patterns (GlassCard containers, color semantics)
- Handle authentication errors (401/403 trigger re-login)

### Common Patterns
- **Date handling**: eSchool API uses Unix timestamps (milliseconds). Convert with `Date(timeIntervalSince1970: timestamp/1000)`
- **Request headers**: All requests include specific headers (User-Agent: "eSchoolMobile", Accept-Language: "ru-RU,en,*", etc.)
- **Error handling**: Logged requests/responses help debug API issues
- **Session cookies**: Automatically included via `HTTPCookie.requestHeaderFields(with: cookies)`

### Debugging
- Request/response logging enabled in `APIService.logRequest()` and `logResponse()`
- Check console for `DEBUG:` prefixed messages during authentication
- Session cookie persistence issues: Verify Keychain access with `KeychainHelper.shared`
