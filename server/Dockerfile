# ============================================
# Stage 1: Builder - Compile TypeScript
# ============================================
FROM node:20-alpine AS builder

WORKDIR /app

# Copy package files
COPY package*.json ./
COPY tsconfig*.json ./

# Install ALL dependencies (including devDependencies for TypeScript compilation)
RUN npm install

# Copy source code
COPY src ./src

# Compile TypeScript to JavaScript
RUN npm run build

# ============================================
# Stage 2: Production - Run compiled code
# ============================================
FROM node:20-alpine

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install ONLY production dependencies
RUN npm install --omit=dev

# Copy compiled JavaScript from builder stage
COPY --from=builder /app/dist ./dist

# Copy other necessary files
COPY db ./db

EXPOSE 3001

# Run compiled JavaScript (NOT ts-node)
CMD ["node", "dist/index.js"]
