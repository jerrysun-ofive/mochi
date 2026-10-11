# Mochi Pro backend

The production Mochi Pro API is hosted by the separate `mochi-web` Vercel project at:

```text
https://www.trymochi.dev/api
```

The macOS app authenticates with its Supabase user JWT, then calls Vercel for billing and hosted AI. Vercel validates that JWT with Supabase, stores subscription and quota state in Supabase, and calls Stripe, TypeSafe Jev, and DeepSeek using server-only environment variables.

The implementation and deployment instructions live in:

```text
/Users/js/Desktop/Desktop/mochi-dev/mochi-web/DEPLOYMENT.md
```

Provider secrets must be configured in Vercel. They must not be stored in this repository, the macOS application, or any `VITE_`/public environment variable.
