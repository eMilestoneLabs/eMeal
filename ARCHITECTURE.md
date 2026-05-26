# Smart Hostel - Architecture Documentation

## System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                       Flutter App                            │
├─────────────────────────────────────────────────────────────┤
│
│  ┌──────────────────────────────────────────────────────┐
│  │              Presentation Layer (UI)                 │
│  ├──────────────────────────────────────────────────────┤
│  │  Features/
│  │  ├─ Auth (Splash, Login)
│  │  ├─ Student
│  │  │   ├─ Dashboard
│  │  │   ├─ Meals
│  │  │   ├─ Attendance
│  │  │   ├─ Profile
│  │  │   └─ Navigation
│  │  └─ Admin
│  │      ├─ Dashboard
│  │      ├─ Meals Management
│  │      ├─ Attendance Tracking
│  │      ├─ Settings
│  │      └─ Navigation
│  └──────────────────────────────────────────────────────┘
│                          ▲
│                          │ Uses
│                          ▼
│  ┌──────────────────────────────────────────────────────┐
│  │            Shared Layer (Reusable)                   │
│  ├──────────────────────────────────────────────────────┤
│  │  Widgets/
│  │  ├─ GlassCard
│  │  ├─ PremiumButton
│  │  └─ SectionTitle
│  │
│  │  Models/
│  │  ├─ UserModel
│  │  ├─ MealModel
│  │  └─ AttendanceModel
│  │
│  │  Enums/
│  │  ├─ UserRole
│  │  └─ MealType
│  └──────────────────────────────────────────────────────┘
│                          ▲
│                          │ Uses
│                          ▼
│  ┌──────────────────────────────────────────────────────┐
│  │            Core Layer (Utilities)                    │
│  ├──────────────────────────────────────────────────────┤
│  │  Theme/
│  │  ├─ app_colors.dart
│  │  └─ app_theme.dart (Material 3)
│  │
│  │  Responsive/
│  │  └─ responsive.dart (Breakpoints)
│  │
│  │  Constants/
│  │  ├─ app_spacing.dart
│  │  └─ app_radius.dart
│  │
│  │  Utils/
│  │  └─ date_utils.dart
│  └──────────────────────────────────────────────────────┘
│                          ▲
│                          │ Uses
│                          ▼
│  ┌──────────────────────────────────────────────────────┐
│  │           Data Layer (Services & Repos)              │
│  ├──────────────────────────────────────────────────────┤
│  │  Repositories/
│  │  ├─ AuthRepository
│  │  ├─ MealRepository
│  │  └─ AttendanceRepository
│  │
│  │  Mock Services/ (Will be replaced with APIs)
│  │  ├─ MockAuthService
│  │  ├─ MockMealService
│  │  └─ MockAttendanceService
│  └──────────────────────────────────────────────────────┘
│                          ▲
│                          │ Calls
│                          ▼
│  ┌──────────────────────────────────────────────────────┐
│  │          External (APIs, Databases)                  │
│  ├──────────────────────────────────────────────────────┤
│  │  [Backend APIs] - To be implemented
│  │  [Database] - To be connected
│  └──────────────────────────────────────────────────────┘
│
└─────────────────────────────────────────────────────────────┘
```

## Data Flow

### Authentication Flow
```
LoginScreen
    │
    ├─> AuthRepository.login()
    │       │
    │       ├─> MockAuthService.login()
    │       │       │
    │       │       └─> Return UserModel
    │       │
    │       └─> Save user state
    │
    └─> Navigate to DashboardRouter
            │
            ├─> Check user.role.isAdmin
            │
            ├─ YES ─> AdminNavigationScreen
            │
            └─ NO ──> StudentNavigationScreen
```

### Meal Display Flow
```
StudentDashboardScreen
    │
    ├─> MealRepository.getMeals()
    │       │
    │       ├─> MockMealService.getMeals()
    │       │       │
    │       │       └─> Return List<MealModel>
    │       │
    │       └─> Return data
    │
    ├─> Filter enabled meals (meal.isEnabled == true)
    │
    └─> Build UI with meal data
            │
            └─> Display cards with meal info
```

### Attendance Tracking Flow
```
Student marks attendance
    │
    ├─> AttendanceRepository.markAttendance()
    │       │
    │       ├─> MockAttendanceService.markAttendance()
    │       │       │
    │       │       └─> Save to local list
    │       │
    │       └─> Return AttendanceModel
    │
    └─> Update UI to show confirmation
```

## Feature Separation

### Student Module
- **Location**: `lib/features/student/`
- **Contains**: Dashboard, Meals, Attendance, Profile
- **Visibility**: Only shown to users with role = `student`
- **Key Operations**:
  - View available meals
  - Mark attendance
  - View attendance history
  - Manage profile

### Admin Module
- **Location**: `lib/features/admin/`
- **Contains**: Dashboard, Meal Management, Attendance Tracking, Settings
- **Visibility**: Only shown to users with role = `admin`, `messManager`, `hostelManager`, `hostelAdmin`
- **Key Operations**:
  - Create/edit/delete meals
  - Enable/disable meals
  - View meal attendance
  - Manage organization settings

## Key Design Patterns

### 1. Repository Pattern
```dart
// UI always goes through Repository
Widget → Repository → Service → Data Source

// Easy to swap implementations
MockMealService ─┐
                 ├─> MealRepository ─> UI
ApiMealService ──┘
```

### 2. Feature-First Organization
```
Benefits:
- Clear separation of concerns
- Easy to maintain
- Simple to add new features
- Scalable structure
```

### 3. Responsive Design
```dart
Responsive.isMobile(context)   // < 600px
Responsive.isTablet(context)   // 600-900px
Responsive.isDesktop(context)  // > 900px

// Automatic layout adjustment
```

### 4. Theme Centralization
```dart
// All colors in one place
AppColors.primary
AppColors.success
AppColors.error

// All spacing in one place
AppSpacing.md
AppSpacing.lg

// All theme in one place
AppTheme.lightTheme
AppTheme.darkTheme
```

## Role-Based Behavior

### Admin Disables Meal

```
Admin toggles meal disabled
    │
    ├─> MealRepository.toggleMealStatus(id, false)
    │       │
    │       ├─> meal.isEnabled = false
    │       │
    │       └─> Persist change
    │
    └─> Student screens update
            │
            ├─> StudentDashboard filters out disabled meal
            │
            ├─> MealsScreen shows only enabled meals
            │
            └─> But attendance still tracked for that meal
```

### Important Behavior
- When meal is disabled: UI hides it from students
- When meal is disabled: Attendance system still works
- Students can't see disabled meals
- Admin can still track attendance for disabled meals

## State Management Approach

**Current**: StatefulWidget (Simple, MVP-ready)
**Future**: Add Riverpod/Bloc when complexity grows

Benefits of current approach:
- No extra dependencies
- Easy to understand
- Performant for MVP
- Quick to develop

## Error Handling Strategy

### Current Implementation
```dart
try {
  final data = await repository.getData();
  setState(() {
    _data = data;
    _isLoading = false;
  });
} catch (e) {
  // Show error to user
  ScaffoldMessenger.show(SnackBar(...));
}
```

### Future Improvements
- Centralized error handling
- Retry logic
- Offline support
- Error logging

## Responsive Layout Strategy

### Breakpoints
```
Mobile   (< 600px):  1 column layout
Tablet   (600-900px): 2 column layout
Desktop  (> 900px):   3 column layout
```

### Implementation
```dart
// In any screen
final columns = Responsive.gridColumns(context);
final padding = Responsive.horizontalPadding(context);

GridView.builder(
  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: columns,
    mainAxisSpacing: padding,
    crossAxisSpacing: padding,
  ),
  // ...
)
```

## Future Architecture Considerations

### When Adding State Management
```
Current:  Widget → Repository → Service
Future:   Widget → Provider/Stream ← Repository ← Service
```

### When Adding Backend
```
Current:  Mock Service
Future:   API Service (REST/GraphQL) ← Dio/Retrofit
```

### When Adding Database
```
Current:  In-memory
Future:   Local (Hive/SQLite) ← Remote (Backend DB)
```

### When Adding Advanced Features
```
Current:  Simple widgets
Future:   Advanced (Notifications, Sync, Caching)
```

## Scalability Notes

✅ **Scales Well**:
- Adding new student features
- Adding new admin features
- Creating new roles
- Expanding meal types
- Adding more attendance fields

⚠️ **May Need Refactoring**:
- Complex state management (add Riverpod)
- Real-time sync (add WebSockets)
- Offline-first (add Hive/SQLite)
- Advanced caching (add custom layer)

## Performance Considerations

1. **List Rendering**: Use `.builder()` for large lists
2. **Images**: Add caching when implementing image uploads
3. **API Calls**: Add debouncing for search/filter
4. **State Updates**: Minimize rebuild scope
5. **Navigation**: Lazy load feature modules if needed

## Security Baseline

Current MVP:
- ✅ Local session management
- ✅ Role-based navigation
- ❌ Real authentication
- ❌ Encrypted storage

Future:
- JWT tokens
- Secure token storage
- HTTPS enforcement
- Input validation
- Rate limiting

---

**This architecture supports MVP development while remaining production-ready for scaling.**
