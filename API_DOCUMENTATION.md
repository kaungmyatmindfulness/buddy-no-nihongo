# Wise Owl Japanese Learning Platform - API Documentation

## Overview

The Wise Owl platform is a microservices-based Japanese vocabulary learning application built with Go. It consists of three main services accessible through an Nginx API Gateway.

### Base URLs

- **Development**: `http://localhost:8080` (API Gateway)
- **Direct Service Access** (Development only):
  - Users Service: `http://localhost:8081`
  - Content Service: `http://localhost:8082`
  - Quiz Service: `http://localhost:8083`

### Architecture

- **API Gateway**: Nginx routes requests to appropriate services
- **Authentication**: Auth0 JWT tokens for protected endpoints
- **Database**: MongoDB with separate databases per service

---

## Authentication

Protected endpoints require an Auth0 JWT token in the Authorization header:

```http
Authorization: Bearer <your-jwt-token>
```

### Error Responses for Authentication

```json
{
	"error": "invalid_token",
	"message": "Failed to validate token."
}
```

---

## Content Service

The Content Service manages Japanese vocabulary content and lessons. **All endpoints are public** (no authentication required).

### Base Path

- Via Gateway: `/api/v1/content/` (Currently has routing issues)
- Direct Access: `http://localhost:8082/api/v1/`

### Endpoints

#### 1. Get All Lessons

**GET** `/api/v1/lessons`

Retrieves a list of all available lesson identifiers.

**Response:**

```json
{
  "lessons": [
    "preliminary-lesson",
    "lesson-1",
    "lesson-2",
    "lesson-3",
    ...
    "lesson-50"
  ]
}
```

**Example:**

```bash
curl http://localhost:8082/api/v1/lessons
```

#### 2. Get Lesson Content

**GET** `/api/v1/lessons/{lessonId}`

Retrieves all vocabulary entries for a specific lesson.

**Path Parameters:**

- `lessonId` (string): The lesson identifier (e.g., "lesson-1", "preliminary-lesson")

**Response:**

```json
[
	{
		"_id": "687d32dc8d28bf14214a8f19",
		"kana": "あなた",
		"kanji": "貴方",
		"furigana": "<ruby><rb>貴方</rb><rp>(</rp><rt>あなた</rt><rp>)</rp></ruby>",
		"romaji": "anata",
		"english": "you",
		"burmese": "သင်/ခင်ဗျား",
		"lesson": "lesson-1",
		"type": "vocabulary",
		"word-class": "pronoun"
	},
	{
		"_id": "687d32dc8d28bf14214a8f1b",
		"kana": "あのかた",
		"kanji": "あの方",
		"furigana": "<ruby><rb>あの方</rb><rp>(</rp><rt>あのかた</rt><rp>)</rp></ruby>",
		"romaji": "ano kata",
		"english": "polite equivalent of あのひと",
		"burmese": "ထိုပုဂ္ဂိုလ်",
		"lesson": "lesson-1",
		"type": "vocabulary",
		"word-class": "pronoun"
	}
]
```

**Empty Response (Invalid lesson):**

```json
[]
```

**Example:**

```bash
curl http://localhost:8082/api/v1/lessons/lesson-1
```

### Vocabulary Entry Schema

| Field        | Type        | Description                                            |
| ------------ | ----------- | ------------------------------------------------------ |
| `_id`        | string      | MongoDB ObjectId                                       |
| `kana`       | string      | Japanese hiragana/katakana reading                     |
| `kanji`      | string/null | Japanese kanji characters (null if not applicable)     |
| `furigana`   | string/null | HTML ruby markup for kanji pronunciation               |
| `romaji`     | string      | Romanized Japanese                                     |
| `english`    | string      | English translation                                    |
| `burmese`    | string      | Burmese translation                                    |
| `lesson`     | string      | Lesson identifier                                      |
| `type`       | string      | Entry type (e.g., "vocabulary", "set-phrase")          |
| `word-class` | string      | Grammatical category (e.g., "pronoun", "noun", "verb") |

---

## Users Service

The Users Service manages user profiles and account information. **All endpoints require authentication**.

### Base Path

- Via Gateway: `/api/v1/users/` (Routing issues - use direct access)
- Direct Access: `http://localhost:8081/api/v1/users/`

### Endpoints

#### 1. User Onboarding

**POST** `/api/v1/users/onboarding`

Creates a new user profile after Auth0 sign-up.

**Headers:**

```http
Authorization: Bearer <jwt-token>
Content-Type: application/json
```

**Request Body:**

```json
{
	"username": "john_doe",
	"email": "john@example.com"
}
```

**Request Schema:**
| Field | Type | Required | Validation |
|-------|------|----------|------------|
| `username` | string | Yes | - |
| `email` | string | Yes | Valid email format |

**Response (201 Created):**

```json
{
	"_id": "64a1b2c3d4e5f6g7h8i9j0k1",
	"auth0_id": "auth0|64a1b2c3d4e5f6g7h8i9j0k1",
	"username": "john_doe",
	"email": "john@example.com",
	"notification_prefs": {
		"enabled": false
	},
	"created_at": "2025-07-30T10:30:00Z",
	"updated_at": "2025-07-30T10:30:00Z"
}
```

**Error Responses:**

```json
// Bad Request (400)
{
  "error": "invalid_request",
  "message": "validation error details"
}

// Conflict (409) - User already exists
{
  "error": "user_exists",
  "message": "User profile already exists."
}

// Internal Server Error (500)
{
  "error": "create_failed"
}
```

**Example:**

```bash
curl -X POST http://localhost:8081/api/v1/users/onboarding \
  -H "Authorization: Bearer <jwt-token>" \
  -H "Content-Type: application/json" \
  -d '{"username": "john_doe", "email": "john@example.com"}'
```

#### 2. Get User Profile

**GET** `/api/v1/users/me/profile`

Retrieves the current user's profile information.

**Headers:**

```http
Authorization: Bearer <jwt-token>
```

**Response (200 OK):**

```json
{
	"_id": "64a1b2c3d4e5f6g7h8i9j0k1",
	"auth0_id": "auth0|64a1b2c3d4e5f6g7h8i9j0k1",
	"username": "john_doe",
	"email": "john@example.com",
	"notification_prefs": {
		"enabled": false
	},
	"created_at": "2025-07-30T10:30:00Z",
	"updated_at": "2025-07-30T10:30:00Z"
}
```

**Error Responses:**

```json
// Not Found (404)
{
  "error": "not_found",
  "message": "User profile not found."
}

// Internal Server Error (500)
{
  "error": "database_error"
}
```

**Example:**

```bash
curl http://localhost:8081/api/v1/users/me/profile \
  -H "Authorization: Bearer <jwt-token>"
```

#### 3. Update User Profile

**PATCH** `/api/v1/users/me/profile`

Updates the current user's profile information.

**Headers:**

```http
Authorization: Bearer <jwt-token>
Content-Type: application/json
```

**Request Body:**

```json
{
	"username": "new_username",
	"notification_preferences": {
		"enabled": true
	}
}
```

**Request Schema:**
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `username` | string | No | New username |
| `notification_preferences` | object | No | Notification settings |
| `notification_preferences.enabled` | boolean | No | Enable/disable notifications |

**Response (204 No Content):**

```
(Empty response body)
```

**Error Responses:**

```json
// Bad Request (400) - No updates provided
{
  "error": "no_updates_provided"
}

// Bad Request (400) - Invalid request
{
  "error": "invalid_request",
  "message": "validation error details"
}

// Not Found (404)
{
  "error": "not_found"
}

// Internal Server Error (500)
{
  "error": "update_failed"
}
```

**Example:**

```bash
curl -X PATCH http://localhost:8081/api/v1/users/me/profile \
  -H "Authorization: Bearer <jwt-token>" \
  -H "Content-Type: application/json" \
  -d '{"username": "new_username"}'
```

#### 4. Delete User Account

**DELETE** `/api/v1/users/me`

Permanently deletes the current user's account.

**Headers:**

```http
Authorization: Bearer <jwt-token>
```

**Response (204 No Content):**

```
(Empty response body)
```

**Error Responses:**

```json
// Not Found (404)
{
  "error": "not_found"
}

// Internal Server Error (500)
{
  "error": "delete_failed"
}
```

**Example:**

```bash
curl -X DELETE http://localhost:8081/api/v1/users/me \
  -H "Authorization: Bearer <jwt-token>"
```

---

## Quiz Service

The Quiz Service manages user learning progress, specifically tracking words that users answered incorrectly. **All endpoints require authentication**.

### Base Path

- Via Gateway: `/api/v1/quiz/` (Routing issues - use direct access)
- Direct Access: `http://localhost:8083/api/v1/quiz/`

### Endpoints

#### 1. Record Incorrect Word

**POST** `/api/v1/quiz/incorrect-words`

Records that a user answered a vocabulary word incorrectly. Uses upsert logic to avoid duplicates.

**Headers:**

```http
Authorization: Bearer <jwt-token>
Content-Type: application/json
```

**Request Body:**

```json
{
	"vocabulary_id": "687d32dc8d28bf14214a8f19"
}
```

**Request Schema:**
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `vocabulary_id` | string | Yes | MongoDB ObjectId of the vocabulary entry |

**Response (200 OK):**

```json
{
	"message": "Incorrect word recorded successfully"
}
```

**Error Responses:**

```json
// Bad Request (400)
{
  "error": "invalid_request"
}

// Internal Server Error (500)
{
  "error": "database_error"
}
```

**Example:**

```bash
curl -X POST http://localhost:8083/api/v1/quiz/incorrect-words \
  -H "Authorization: Bearer <jwt-token>" \
  -H "Content-Type: application/json" \
  -d '{"vocabulary_id": "687d32dc8d28bf14214a8f19"}'
```

#### 2. Get Incorrect Words

**GET** `/api/v1/quiz/incorrect-words`

Retrieves all vocabulary words that the user has answered incorrectly, along with the actual vocabulary data from the Content Service.

**Headers:**

```http
Authorization: Bearer <jwt-token>
```

**Response (200 OK):**

```json
[
	{
		"_id": "64a1b2c3d4e5f6g7h8i9j0k1",
		"user_id": "auth0|64a1b2c3d4e5f6g7h8i9j0k1",
		"vocabulary_id": "687d32dc8d28bf14214a8f19",
		"recorded_at": "2025-07-30T10:30:00Z",
		"vocabulary_data": {
			"_id": "687d32dc8d28bf14214a8f19",
			"kana": "あなた",
			"kanji": "貴方",
			"furigana": "<ruby><rb>貴方</rb><rp>(</rp><rt>あなた</rt><rp>)</rp></ruby>",
			"romaji": "anata",
			"english": "you",
			"burmese": "သင်/ခင်ဗျား",
			"lesson": "lesson-1",
			"type": "vocabulary",
			"word-class": "pronoun"
		}
	}
]
```

**Empty Response:**

```json
[]
```

**Error Responses:**

```json
// Internal Server Error (500)
{
	"error": "database_error"
}
```

**Example:**

```bash
curl http://localhost:8083/api/v1/quiz/incorrect-words \
  -H "Authorization: Bearer <jwt-token>"
```

#### 3. Clear Incorrect Words

**DELETE** `/api/v1/quiz/incorrect-words`

Removes all incorrect word records for the current user. Useful for resetting learning progress.

**Headers:**

```http
Authorization: Bearer <jwt-token>
```

**Response (200 OK):**

```json
{
	"message": "Incorrect words cleared successfully",
	"deleted_count": 5
}
```

**Error Responses:**

```json
// Internal Server Error (500)
{
	"error": "database_error"
}
```

**Example:**

```bash
curl -X DELETE http://localhost:8083/api/v1/quiz/incorrect-words \
  -H "Authorization: Bearer <jwt-token>"
```

---

## Health Check Endpoints

All services provide health check endpoints for monitoring and load balancer health checks.

### Standard Health Endpoints

Available on all services:

#### 1. Basic Health Check

**GET** `/health`

Returns basic service health information.

**Response (200 OK):**

```json
{
	"status": "healthy",
	"service": "Users Service",
	"timestamp": "2025-07-30T10:30:00Z",
	"uptime": "1h23m45s",
	"database": "connected"
}
```

#### 2. Readiness Check

**GET** `/health/ready`

Returns whether the service is ready to accept requests.

**Response (200 OK):**

```json
{
	"ready": true
}
```

#### 3. Liveness Check

**GET** `/health/live`

Returns whether the service is alive (same as `/health/ready`).

**Response (200 OK):**

```json
{
	"ready": true
}
```

### API Gateway Health

**GET** `/health-check`

**Response (200 OK):**

```json
{
	"status": "healthy",
	"service": "Nginx API Gateway"
}
```

---

## Error Handling

### Standard Error Response Format

```json
{
	"error": "error_code",
	"message": "Human-readable error description"
}
```

### Common Error Codes

| Code              | HTTP Status | Description                      |
| ----------------- | ----------- | -------------------------------- |
| `invalid_token`   | 401         | JWT token is invalid or missing  |
| `invalid_request` | 400         | Request body validation failed   |
| `not_found`       | 404         | Resource not found               |
| `user_exists`     | 409         | User already exists (onboarding) |
| `database_error`  | 500         | Database operation failed        |
| `create_failed`   | 500         | Resource creation failed         |
| `update_failed`   | 500         | Resource update failed           |
| `delete_failed`   | 500         | Resource deletion failed         |

---

## Rate Limiting

Currently, no rate limiting is implemented. In production, consider implementing rate limiting at the API Gateway level.

---

## CORS

CORS is handled by each individual service. Ensure proper CORS configuration for frontend applications.

---

## Service Communication

### Internal gRPC Communication

The Quiz Service communicates with the Content Service via gRPC for vocabulary data enrichment:

- **Content Service gRPC Port**: 50052
- **Protocol**: gRPC over HTTP/2
- **Service**: `ContentService`
- **Method**: `GetVocabularyBatch`

This is used internally when fetching incorrect words to include full vocabulary details.

---

## Development Notes

### Current Known Issues

1. **Nginx Routing**: API Gateway routing has path conflicts. Use direct service URLs for development.
2. **Authentication**: Auth0 configuration required for protected endpoints.
3. **HTTPS**: Development environment uses HTTP. Production should use HTTPS.

### Service Ports (Development)

| Service         | HTTP Port | gRPC Port |
| --------------- | --------- | --------- |
| API Gateway     | 8080      | -         |
| Users Service   | 8081      | -         |
| Content Service | 8082      | 50052     |
| Quiz Service    | 8083      | -         |
| MongoDB         | 27017     | -         |

### Environment Variables

Required environment variables for full functionality:

- `AUTH0_DOMAIN`: Auth0 domain for JWT validation
- `AUTH0_AUDIENCE`: Auth0 audience for JWT validation
- `DB_TYPE`: Database type (e.g., "mongodb")
- `DB_NAME`: Database name prefix

---

## Examples and Testing

### Complete Workflow Example

1. **Get Available Lessons:**

```bash
curl http://localhost:8082/api/v1/lessons
```

2. **Get Lesson Content:**

```bash
curl http://localhost:8082/api/v1/lessons/lesson-1
```

3. **Create User Profile (with valid JWT):**

```bash
curl -X POST http://localhost:8081/api/v1/users/onboarding \
  -H "Authorization: Bearer <jwt-token>" \
  -H "Content-Type: application/json" \
  -d '{"username": "learner123", "email": "learner@example.com"}'
```

4. **Record Incorrect Answer (with valid JWT):**

```bash
curl -X POST http://localhost:8083/api/v1/quiz/incorrect-words \
  -H "Authorization: Bearer <jwt-token>" \
  -H "Content-Type: application/json" \
  -d '{"vocabulary_id": "687d32dc8d28bf14214a8f19"}'
```

5. **Review Incorrect Words (with valid JWT):**

```bash
curl http://localhost:8083/api/v1/quiz/incorrect-words \
  -H "Authorization: Bearer <jwt-token>"
```

---

_Last Updated: July 30, 2025_
