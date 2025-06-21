// FILE: lib/auth/middleware.go
// This package contains the shared Gin middleware for validating Auth0 JWTs.

package auth

import (
	"context"
	"log"
	"net/http"
	"net/url"
	"time"

	jwtmiddleware "github.com/auth0/go-jwt-middleware/v2"
	"github.com/auth0/go-jwt-middleware/v2/jwks"
	"github.com/auth0/go-jwt-middleware/v2/validator"
	"github.com/gin-gonic/gin"
)

// CustomClaims contains custom data we want to be available in our JWT.
type CustomClaims struct {
	Scope string `json:"scope"`
}

// Validate satisfies the validator.CustomClaims interface.
func (c CustomClaims) Validate(ctx context.Context) error {
	return nil
}

// EnsureValidToken creates a new Gin middleware that checks the validity of an Auth0 JWT.
func EnsureValidToken(domain, audience string) gin.HandlerFunc {
	issuerURL, err := url.Parse("https://" + domain + "/")
	if err != nil {
		log.Fatalf("Failed to parse issuer url: %v", err)
	}

	// Caching provider to fetch and cache JWKS from Auth0.
	provider := jwks.NewCachingProvider(issuerURL, 5*time.Minute)

	// JWT validator with configured claims.
	jwtValidator, err := validator.New(
		provider.KeyFunc,
		validator.RS256,
		issuerURL.String(),
		[]string{audience},
		validator.WithCustomClaims(func() validator.CustomClaims {
			return &CustomClaims{}
		}),
		validator.WithAllowedClockSkew(time.Minute),
	)
	if err != nil {
		log.Fatalf("Failed to set up JWT validator: %v", err)
	}

	// The actual middleware logic.
	middleware := jwtmiddleware.New(
		jwtValidator.ValidateToken,
		jwtmiddleware.WithErrorHandler(func(w http.ResponseWriter, r *http.Request, err error) {
			log.Printf("Token validation error: %v", err)
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusUnauthorized)
			w.Write([]byte(`{"error":"invalid_token","message":"Failed to validate token."}`))
		}),
	)

	return func(c *gin.Context) {
		handler := middleware.CheckJWT(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			// Token is valid, proceed to the next handler.
			// Extract the user ID ('sub' claim) and set it in the Gin context.
			claims := r.Context().Value(jwtmiddleware.ContextKey{}).(*validator.ValidatedClaims)
			c.Set("userID", claims.RegisteredClaims.Subject)
			c.Next()
		}))
		handler.ServeHTTP(c.Writer, c.Request)
	}
}
