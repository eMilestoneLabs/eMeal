# 🚀 MealAttend - Setup & Development Guide

Enterprise-grade Meal, Attendance, Group, Event and Analytics Management Platform built with Flutter, NestJS, PostgreSQL, Redis, BullMQ and MinIO.

---

# 🎯 Platform Overview

MealAttend is a multi-tenant SaaS platform designed for:

* 🏫 Hostels
* 🏢 Companies
* 🏭 Factories
* 🎓 Colleges
* 🏛️ Institutions
* 🎉 Events & Functions

The platform provides:

✅ Meal Management

✅ Attendance Management

✅ Group Management

✅ Event Management

✅ Guest Registration

✅ Family Registration

✅ Analytics & Reporting

✅ Realtime Updates

✅ Notification System

✅ CSV/XLSX Export

✅ Multi-Tenant Organizations

✅ JWT Authentication

✅ Refresh Token Rotation

✅ Audit Logging

✅ Production Deployment

---

# 🏗️ Technology Stack

## 📱 Frontend

* Flutter
* Dart
* Material 3
* Dio
* Provider
* ChangeNotifier
* ValueNotifier
* Socket.IO Client

## ⚙️ Backend

* NestJS
* TypeScript
* Prisma ORM
* PostgreSQL
* Redis
* BullMQ
* MinIO

## ☁️ Infrastructure

* Docker
* Docker Compose
* Nginx
* GitHub Actions
* CodeQL
* Semgrep
* Trivy
* Gitleaks
* Contabo VPS

---

# 👥 Supported Roles

## 👨‍🎓 Student

### Features

* Dashboard
* Meal Schedule
* Meal Preferences
* Attendance Marking
* Attendance History
* Attendance Analytics
* Notifications
* Profile Management
* Settings

---

## 👨‍💼 Organization Admin

### Features

* Dashboard
* Group Management
* Member Management
* Meal Management
* Attendance Monitoring
* Reports
* Analytics
* Notifications
* Settings

---

## 🎉 Event Admin

### Features

* Event Dashboard
* Guest Management
* Family Registration Tracking
* Event Meal Management
* Attendance Monitoring
* Event Statistics
* Reports

---

## 🎫 Event Guest

### Features

* Event Registration
* Family Member Registration
* Meal Selection
* Attendance Confirmation
* Registration Updates

---

# 🔒 Architecture Governance

## Contract Governance

Frontend and Backend contracts are locked.

### Rules

✅ Existing response fields cannot be removed

✅ Existing enum values cannot change

✅ Existing API response shapes cannot change

✅ Existing DTO contracts cannot change

✅ Additive changes only

---

## State Management Governance

### Approved

* StatefulWidget
* ChangeNotifier
* ValueNotifier
* Provider

### Not Approved

❌ Riverpod

❌ Bloc

❌ Redux

❌ GetX

❌ MobX

---

## Backend Governance

Approved:

* NestJS
* PostgreSQL
* Prisma
* Redis
* BullMQ
* MinIO

Not Approved:

❌ Firebase

❌ Supabase

❌ MongoDB

❌ GraphQL

❌ Sequelize

❌ TypeORM

---

# 🏗️ System Architecture

```text
Flutter App
     │
     ▼
Provider / ChangeNotifier
     │
     ▼
Repositories
     │
     ▼
DioApiService
     │
     ▼
NestJS Backend
     │
 ┌───┼─────────────┬─────────────┐
 ▼   ▼             ▼             ▼

PostgreSQL       Redis        BullMQ

                 │
                 ▼

             Realtime

                 │
                 ▼

               MinIO
```

---

# 🔄 Realtime Architecture

```text
Flutter
   │
Socket.IO
   │
NestJS Gateway
   │
Redis Adapter
```

### Realtime Events

* attendance.marked.v1
* attendance.overridden.v1
* guest.joined.v1
* guest.updated.v1
* meal.updated.v1
* event.updated.v1
* dashboard.updated.v1

---

# 📁 Project Structure

```text
lib/
│
├── app/
│
├── core/
│
├── shared/
│
├── data/
│   ├── repositories/
│   ├── services/
│   └── models/
│
├── features/
│   ├── auth/
│   ├── student/
│   ├── admin/
│   ├── event_admin/
│   └── event_guest/
│
└── main.dart
```

---

# 🚀 Quick Start

## Prerequisites

### Flutter

```bash
flutter --version
```

Required:

```text
Flutter 3.22+
Dart 3.5+
Java 17+
Android SDK 24+
```

---

## Clone Repository

```bash
git clone <repository-url>

cd smart_meal_management
```

---

## Install Dependencies

```bash
flutter pub get
```

---

## Verify Installation

```bash
flutter doctor
```

All checks should be green.

---

## Run Development Build

```bash
flutter run
```

---

## Run Specific Device

```bash
flutter devices

flutter run -d <device-id>
```

---

## Run Release Build

```bash
flutter run --release
```

---

# 🧪 Testing

## Run Unit Tests

```bash
flutter test
```

---

## Analyze Code

```bash
flutter analyze
```

---

## Check Formatting

```bash
dart format .
```

---

## Complete Verification

```bash
flutter test

flutter analyze

dart format --set-exit-if-changed .
```

---

# 📦 Production Builds

## Android APK

```bash
flutter build apk --release
```

Output:

```text
build/app/outputs/flutter-apk/app-release.apk
```

---

## Android App Bundle

```bash
flutter build appbundle --release
```

Output:

```text
build/app/outputs/bundle/release/app-release.aab
```

Recommended for Play Store deployment.

---

## iOS Release

```bash
flutter build ios --release
```

---

# 🔐 Security Architecture

Implemented:

✅ JWT Authentication

✅ Refresh Token Rotation

✅ Organization Isolation

✅ Audit Logging

✅ DTO Validation

✅ Role-Based Authorization

✅ Secure File Upload Validation

✅ HTTPS Enforcement

✅ WebSocket JWT Validation

✅ Rate Limiting

---

# 📊 Analytics & Reporting

Supported:

* Attendance Analytics
* Meal Analytics
* Event Analytics
* Dashboard KPIs
* CSV Export
* XLSX Export
* Attendance Reports
* Event Guest Reports

---

# 🔔 Notification Architecture

```text
Application Event
        │
        ▼
BullMQ Queue
        │
        ▼
Worker
        │
        ▼
Notification Service
        │
        ▼
Realtime Update
```

---

# 🏢 Multi-Tenant Architecture

```text
Organization
      │
      ▼
Group
      │
      ▼
Members
      │
 ┌────┼────┬────┐
 ▼    ▼    ▼    ▼

Meals Attendance Events Analytics
```

Rules:

✅ Organization isolation enforced

✅ JWT-based organization context

✅ Cross-organization access blocked

✅ Audit trail preserved

---

# 🚀 CI/CD Pipeline

GitHub Actions Pipeline Includes:

✅ Build Verification

✅ Type Checking

✅ Unit Tests

✅ Feature Tests

✅ Integration Tests

✅ Smoke Tests

✅ Performance Tests

✅ Security Scanning

✅ CodeQL

✅ Semgrep

✅ Trivy

✅ Gitleaks

✅ Release Gate

---

# ☁️ Production Deployment

Target Environment:

✅ Ubuntu 24.04

✅ Contabo VPS

✅ Docker

✅ Docker Compose

✅ Nginx

✅ PostgreSQL

✅ Redis

✅ BullMQ

✅ MinIO

✅ SSL (Let's Encrypt)

Deployment Architecture:

```text
Flutter App
      │
      ▼
Nginx
      │
      ▼
NestJS
 ┌────┼────┬────┐
 ▼    ▼    ▼    ▼

PG  Redis BullMQ MinIO
```

---

# ⚡ Performance Guidelines

1. Use builder-based list rendering
2. Minimize widget rebuilds
3. Paginate large datasets
4. Use realtime updates instead of polling
5. Cache static resources
6. Offload heavy jobs to BullMQ workers
7. Optimize database queries

---

# 🛠️ Troubleshooting

## Flutter Dependency Issues

```bash
flutter clean

flutter pub get
```

---

## Android Build Issues

```bash
flutter clean

flutter pub get

flutter build apk --release
```

---

## Verify Environment

```bash
flutter doctor -v
```

---

## Analyze Project

```bash
flutter analyze
```

---

# 🏆 Project Status

Frontend Architecture: ✅ Production Ready

Backend Architecture: ✅ Production Ready

Realtime Architecture: ✅ Enabled

Analytics System: ✅ Enabled

Notification System: ✅ Enabled

Security Architecture: ✅ Enabled

Multi-Tenant Architecture: ✅ Enabled

Contract Governance: ✅ Locked

CI/CD Pipeline: ✅ Enabled

Production Deployment: ⚠ Pending Final Verification

Migration Baseline: ⚠ Pending Verification

---

# 📚 Resources

* Flutter Documentation
* Dart Documentation
* Material Design 3
* NestJS Documentation
* Prisma Documentation
* PostgreSQL Documentation
* Redis Documentation
* BullMQ Documentation
* MinIO Documentation

---

**Built with ❤️ by eMilestone Labs**
