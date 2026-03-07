# Playwright E2E Test Runner
FROM mcr.microsoft.com/playwright:v1.58.0-jammy

WORKDIR /app

# Copy package files
COPY package.json package-lock.json* ./

# Install dependencies
RUN npm ci

# Copy test files
COPY . .

# Set environment variables
ENV CI=true
ENV BASE_URL=http://app:4000

# Run tests
CMD ["npx", "playwright", "test", "--project=chromium"]
