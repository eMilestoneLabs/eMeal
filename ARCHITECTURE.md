# Smart Hostel - Architecture Documentation
## System Architecture
# 🏗️ MealAttend - Architecture Documentation

## 🎯 System Architecture

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│                            MealAttend Flutter App                           │
├──────────────────────────────────────────────────────────────────────────────┤
│
│  ┌──────────────────────────────────────────────────────────────────────┐
│  │                 Presentation Layer (UI & Features)                  │
│  ├──────────────────────────────────────────────────────────────────────┤
│  │                                                                      │
│  │  Features/                                                           │
│  │                                                                      │
│  │  ├─ Auth                                                             │
│  │  │   ├─ Splash                                                       │
│  │  │   ├─ Login                                                        │
│  │  │   ├─ Register                                                     │
│  │  │   ├─ Forgot Password                                              │
│  │  │   └─ OTP Verification                                             │
│  │                                                                      │
│  │  ├─ Student                                                          │
│  │  │   ├─ Dashboard                                                    │
│  │  │   ├─ Meals                                                        │
│  │  │   ├─ Attendance                                                   │
│  │  │   ├─ Profile                                                      │
│  │  │   ├─ Settings                                                     │
│  │  │   └─ Navigation                                                   │
│  │                                                                      │
│  │  ├─ Admin                                                            │
│  │  │   ├─ Dashboard                                                    │
│  │  │   ├─ Groups                                                       │
│  │  │   ├─ Meals                                                        │
│  │  │   ├─ Attendance                                                   │
│  │  │   ├─ Analytics                                                    │
│  │  │   ├─ Reports                                                      │
│  │  │   ├─ Notifications                                                │
│  │  │   ├─ Members                                                      │
│  │  │   ├─ Settings                                                     │
│  │  │   └─ Navigation                                                   │
│  │                                                                      │
│  │  ├─ Event Admin                                                      │
│  │  │   ├─ Dashboard                                                    │
│  │  │   ├─ Guests                                                       │
│  │  │   ├─ Meals                                                        │
│  │  │   ├─ Statistics                                                   │
│  │  │   ├─ Settings                                                     │
│  │  │   └─ Navigation                                                   │
│  │                                                                      │
│  │  └─ Event Guest                                                      │
│  │      ├─ Registration                                                 │
│  │      ├─ Family Members                                               │
│  │      ├─ Meal Selection                                               │
│  │      ├─ Attendance Confirmation                                      │
│  │      └─ Guest Dashboard                                              │
│  │                                                                      │
│  └──────────────────────────────────────────────────────────────────────┘
│                                   ▲
│                                   │ Uses
│                                   ▼
│
│  ┌──────────────────────────────────────────────────────────────────────┐
│  │                    Shared Layer (Reusable)                          │
│  ├──────────────────────────────────────────────────────────────────────┤
│  │                                                                      │
│  │  Widgets/                                                           │
│  │  ├─ Common Components                                               │
│  │  ├─ Form Components                                                 │
│  │  ├─ Dashboard Widgets                                               │
│  │  ├─ Loading Components                                              │
│  │  └─ Error Components                                                │
│  │                                                                      │
│  │  Models/                                                            │
│  │  ├─ UserModel                                                       │
│  │  ├─ OrganizationModel                                               │
│  │  ├─ GroupModel                                                      │
│  │  ├─ MealModel                                                       │
│  │  ├─ AttendanceModel                                                 │
│  │  ├─ EventModel                                                      │
│  │  └─ GuestModel                                                      │
│  │                                                                      │
│  │  Enums/                                                             │
│  │  ├─ UserRole                                                        │
│  │  ├─ GroupType                                                       │
│  │  └─ AttendanceStatus                                                │
│  │                                                                      │
│  └──────────────────────────────────────────────────────────────────────┘
│                                   ▲
│                                   │ Uses
│                                   ▼
│
│  ┌──────────────────────────────────────────────────────────────────────┐
│  │                     Core Layer (Infrastructure)                     │
│  ├──────────────────────────────────────────────────────────────────────┤
│  │                                                                      │
│  │  Theme/                                                             │
│  │  ├─ Material 3                                                      │
│  │  ├─ App Theme                                                       │
│  │  └─ Color System                                                    │
│  │                                                                      │
│  │  Networking/                                                        │
│  │  ├─ DioApiService                                                   │
│  │  ├─ API Interceptors                                                │
│  │  ├─ Auth Headers                                                    │
│  │  └─ Error Handling                                                  │
│  │                                                                      │
│  │  Realtime/                                                          │
│  │  ├─ Socket.IO Client                                                │
│  │  ├─ Event Subscriptions                                             │
│  │  └─ Live Updates                                                    │
│  │                                                                      │
│  │  Configuration/                                                     │
│  │  ├─ Environment Config                                              │
│  │  ├─ API Endpoints                                                   │
│  │  └─ Constants                                                       │
│  │                                                                      │
│  └──────────────────────────────────────────────────────────────────────┘
│                                   ▲
│                                   │ Uses
│                                   ▼
│
│  ┌──────────────────────────────────────────────────────────────────────┐
│  │                      Data Layer (Repositories)                      │
│  ├──────────────────────────────────────────────────────────────────────┤
│  │                                                                      │
│  │  Repositories/                                                      │
│  │  ├─ AuthRepository                                                  │
│  │  ├─ GroupRepository                                                 │
│  │  ├─ MealRepository                                                  │
│  │  ├─ AttendanceRepository                                            │
│  │  └─ EventRepository                                                 │
│  │                                                                      │
│  │  State Management                                                   │
│  │  ├─ StatefulWidget                                                  │
│  │  ├─ ChangeNotifier                                                  │
│  │  ├─ ValueNotifier                                                   │
│  │  └─ Provider                                                        │
│  │                                                                      │
│  └──────────────────────────────────────────────────────────────────────┘
│                                   ▲
│                                   │ REST API + WebSocket
│                                   ▼
│
│  ┌──────────────────────────────────────────────────────────────────────┐
│  │                   Backend Infrastructure Layer                      │
│  ├──────────────────────────────────────────────────────────────────────┤
│  │                                                                      │
│  │  NestJS Backend                                                     │
│  │  ├─ Authentication Module                                           │
│  │  ├─ Organization Module                                             │
│  │  ├─ Group Module                                                    │
│  │  ├─ Meal Module                                                     │
│  │  ├─ Attendance Module                                               │
│  │  ├─ Event Module                                                    │
│  │  ├─ Notification Module                                             │
│  │  ├─ Analytics Module                                                │
│  │  ├─ Export Module                                                   │
│  │  └─ Realtime Gateway                                                │
│  │                                                                      │
│  │  Infrastructure                                                     │
│  │  ├─ PostgreSQL                                                     │
│  │  ├─ Prisma ORM                                                     │
│  │  ├─ Redis                                                          │
│  │  ├─ BullMQ                                                         │
│  │  ├─ MinIO                                                          │
│  │  └─ WebSocket Gateway                                              │
│  │                                                                      │
│  └──────────────────────────────────────────────────────────────────────┘
│
└──────────────────────────────────────────────────────────────────────────────┘
```

### 🚀 Architecture Principles

✅ Feature-First Architecture

✅ Frontend–Backend Contract Lock

✅ Multi-Tenant Organization Isolation

✅ JWT Authentication + Refresh Token Rotation

✅ Dynamic slotKey Meal Governance

✅ Realtime WebSocket Updates

✅ Provider + ChangeNotifier State Management

✅ NestJS + PostgreSQL + Redis + BullMQ + MinIO

✅ Mobile First Design

✅ Production Ready Scalability

❌ No Mock Service Architecture

❌ No MealType Enum Governance

❌ No Riverpod / Bloc / Redux

❌ No Hardcoded Meal Structures

## 🔄 Data Flow

### 🔐 Authentication Flow

```text
Splash Screen
     │
     ▼
Check Stored Session
     │
     ├── Valid Access Token
     │          │
     │          ▼
     │    Load User Profile
     │          │
     │          ▼
     │    Navigate By Role
     │
     └── No Session
                │
                ▼
           Login Screen
                │
                ▼
      AuthRepository.login()
                │
                ▼
          DioApiService
                │
                ▼
        POST /auth/login
                │
                ▼
        JWT Access Token
        Refresh Token
                │
                ▼
         Save Session
                │
                ▼
         Load Profile
                │
                ▼
         Route By Role
                │
 ┌──────────────┼──────────────┬──────────────┐
 ▼              ▼              ▼              ▼
Student      Admin       Event Admin     Event Guest
Portal       Portal        Portal          Portal
```

---

### 🍽️ Meal Loading Flow

```text
Student Meals Screen
        │
        ▼
MealRepository.getMeals()
        │
        ▼
DioApiService
        │
        ▼
GET /meals
        │
        ▼
NestJS Meal Module
        │
        ▼
PostgreSQL
        │
        ▼
Meal Response
        │
        ▼
Repository Mapping
        │
        ▼
MealModel List
        │
        ▼
Render UI
```

---

### ✅ Attendance Marking Flow

```text
Student Marks Attendance
          │
          ▼
AttendanceRepository.markAttendance()
          │
          ▼
DioApiService
          │
          ▼
POST /attendance
          │
          ▼
Attendance Service
          │
          ├── Validate User
          ├── Validate Group
          ├── Validate Window
          └── Upsert Attendance
          │
          ▼
PostgreSQL
          │
          ▼
Attendance Response
          │
          ▼
Update UI
          │
          ▼
Emit WebSocket Event
attendance.marked.v1
```

---

### 🎉 Event Guest Registration Flow

```text
Guest Registration Screen
            │
            ▼
EventRepository.registerGuest()
            │
            ▼
DioApiService
            │
            ▼
POST /events/:id/guests
            │
            ▼
Event Service
            │
            ├── Validate Event
            ├── Validate Capacity
            ├── Validate Guest Data
            └── Create Guest
            │
            ▼
PostgreSQL
            │
            ▼
Guest Created
            │
            ▼
Emit WebSocket Event
guest.joined.v1
            │
            ▼
Update Event Dashboard
```

---

### 📡 Realtime Update Flow

```text
Backend Event
      │
      ▼
NestJS Realtime Gateway
      │
      ▼
Redis Adapter
      │
      ▼
Socket.IO Broadcast
      │
      ▼
Flutter RealtimeService
      │
      ▼
Provider Update
      │
      ▼
UI Refresh
```

Realtime Events:

• attendance.marked.v1

• attendance.overridden.v1

• guest.joined.v1

• guest.updated.v1

• meal.updated.v1

• event.updated.v1

• dashboard.updated.v1

---

### 📊 Analytics & Dashboard Flow

```text
Dashboard Screen
        │
        ▼
Dashboard Provider
        │
        ▼
Analytics API
        │
        ▼
NestJS Analytics Module
        │
        ▼
PostgreSQL Aggregation
        │
        ▼
Analytics Response
        │
        ▼
Charts & KPI Widgets
```

---

### 🔔 Notification Flow

```text
Scheduled Reminder
         │
         ▼
BullMQ Queue
         │
         ▼
Notification Worker
         │
         ▼
Notification Service
         │
         ▼
Create Notification
         │
         ▼
Send Realtime Update
         │
         ▼
User Dashboard
```

# 🎯 Feature Separation

## 👨‍🎓 Student Module

**Location:** `lib/features/student/`

### Features

* 📊 Dashboard
* 🍽️ Meals
* ✅ Attendance
* 👤 Profile
* ⚙️ Settings
* 🔔 Notifications

### Visibility

Accessible only to:

```text
student
```

### Key Operations

* View meal schedule
* Select meal preferences
* Mark attendance
* View attendance history
* View attendance analytics
* Receive attendance reminders
* Manage profile settings

---

## 👨‍💼 Admin Module

**Location:** `lib/features/admin/`

### Features

* 📊 Dashboard
* 👥 Groups
* 🍽️ Meals
* ✅ Attendance
* 📈 Analytics
* 📄 Reports
* 🔔 Notifications
* ⚙️ Settings

### Visibility

Accessible to organization administrators.

### Key Operations

* Manage groups
* Manage members
* Manage meals
* Configure attendance windows
* View analytics
* Export reports
* Manage organization settings
* Send notifications

---

## 🎉 Event Admin Module

**Location:** `lib/features/event_admin/`

### Features

* 📊 Dashboard
* 👥 Guest Management
* 🍽️ Meal Management
* 📈 Statistics
* ⚙️ Settings

### Key Operations

* Create events
* Manage guests
* Manage family registrations
* Track attendance
* View event analytics
* Export guest reports

---

## 🎫 Event Guest Module

**Location:** `lib/features/event_guest/`

### Features

* 📝 Registration
* 👨‍👩‍👧 Family Members
* 🍽️ Meal Selection
* ✅ Attendance Confirmation

### Key Operations

* Register for events
* Add family members
* Select meals
* Update guest information
* Confirm attendance

---

# 🏗️ Key Design Patterns

## 1️⃣ Repository Pattern

```text
UI Layer
    │
    ▼
Provider / ChangeNotifier
    │
    ▼
Repository
    │
    ▼
DioApiService
    │
    ▼
NestJS Backend API
```

Repositories:

* AuthRepository
* GroupRepository
* MealRepository
* AttendanceRepository
* EventRepository

### Benefits

✅ Separation of concerns

✅ Testability

✅ Contract isolation

✅ Backend abstraction

---

## 2️⃣ Feature-First Organization

```text
lib/features/
├── auth/
├── student/
├── admin/
├── event_admin/
└── event_guest/
```

### Benefits

✅ Clear ownership

✅ Modular development

✅ Easier maintenance

✅ Scalable architecture

---

## 3️⃣ Responsive Design

```dart
Responsive.isMobile(context)
Responsive.isTablet(context)
Responsive.isDesktop(context)
```

### Breakpoints

```text
Mobile    < 600px
Tablet    600–900px
Desktop   > 900px
```

### Goals

✅ Mobile-first

✅ Tablet optimized

✅ Desktop compatible

---

## 4️⃣ Theme Centralization

```dart
AppColors
AppSpacing
AppRadius
AppTypography
AppTheme
```

### Benefits

✅ Consistent design

✅ Easier maintenance

✅ Centralized styling

---

# 🔐 Role-Based Behavior

## Meal Visibility Flow

```text
Admin Updates Meal
          │
          ▼
MealRepository
          │
          ▼
Backend API
          │
          ▼
Database Updated
          │
          ▼
Realtime Event
meal.updated.v1
          │
          ▼
Student Dashboard Refresh
```

### Important Rules

✅ Disabled meals are hidden from students

✅ Historical attendance remains intact

✅ Admins retain full visibility

✅ Attendance records are never deleted

---

# ⚡ State Management Approach

MealAttend intentionally uses lightweight state management.

### Approved Architecture

* StatefulWidget
* ChangeNotifier
* ValueNotifier
* Provider

### Governance

❌ Riverpod

❌ Bloc

❌ Redux

❌ GetX

Not part of the approved architecture.

### Benefits

✅ Lightweight

✅ Predictable

✅ Easy onboarding

✅ Low complexity

---

# ⚠️ Error Handling Strategy

```dart
UI
 │
 ▼
Repository
 │
 ▼
DioApiService
 │
 ▼
Backend API
 │
 ▼
Standard Error Response
 │
 ▼
User-Friendly Message
```

### Error Categories

* Validation Errors
* Authentication Errors
* Authorization Errors
* Network Errors
* Server Errors

### Goals

✅ Consistent UX

✅ Contract-compliant errors

✅ Clear user feedback

---

# 📱 Responsive Layout Strategy

### Breakpoints

```text
Mobile    (<600px)
Tablet    (600–900px)
Desktop   (>900px)
```

### Layout Rules

Mobile

* Single column
* Bottom navigation

Tablet

* Two-column layouts
* Expanded cards

Desktop

* Multi-column layouts
* Wider dashboards

---

# 🚀 Architecture Evolution

## Current Production Architecture

```text
Flutter
   │
Provider
   │
Repository
   │
DioApiService
   │
NestJS Backend
   │
PostgreSQL
Redis
BullMQ
MinIO
```

### Realtime Layer

```text
Flutter
   │
Socket.IO
   │
WebSocket Gateway
   │
Redis Adapter
```

### Future Additive Enhancements

* Offline synchronization
* Push notifications
* Advanced analytics
* Enhanced caching

All future enhancements must preserve frontend-backend contracts.

---

# 📈 Scalability Notes

### Designed To Scale

✅ Multi-tenant organizations

✅ Large member counts

✅ High attendance volumes

✅ Multiple event types

✅ Dynamic meal structures

✅ Realtime updates

---

# ⚙️ Performance Considerations

1. Use builder-based list rendering
2. Minimize widget rebuilds
3. Cache static assets
4. Paginate large datasets
5. Use realtime updates instead of excessive polling
6. Process background work through BullMQ

---

# 🔒 Security Architecture

Current Production Security:

✅ JWT Authentication

✅ Refresh Token Rotation

✅ Role-Based Authorization

✅ Organization Isolation

✅ Audit Logging

✅ Input Validation

✅ Rate Limiting

✅ Secure File Uploads

✅ HTTPS Enforcement

✅ WebSocket JWT Validation

### Security Principles

* Never trust client data
* Organization isolation is mandatory
* Authorization before business logic
* Audit critical actions
* Contract-safe validation

---

**🏆 MealAttend Architecture Status**

Frontend Architecture: ✅ Production Ready

Backend Architecture: ✅ Production Ready

Realtime Architecture: ✅ Enabled

Multi-Tenant Architecture: ✅ Enabled

Security Architecture: ✅ Enabled

Scalability Architecture: ✅ Ready

Contract Governance: ✅ Locked

---

**This architecture supports MVP development while remaining production-ready for scaling.**
