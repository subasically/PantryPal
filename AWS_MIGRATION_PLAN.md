# AWS Migration Plan for PantryPal

## Current Architecture (Contabo VPS)

```
┌─────────────────────────────────────────────┐
│         Contabo VPS (62.146.177.62)         │
│                                             │
│  ┌────────────────────────────────────┐    │
│  │   Docker Compose                   │    │
│  │                                    │    │
│  │  ┌──────────────────────────┐     │    │
│  │  │  Node.js API (Alpine)    │     │    │
│  │  │  - Express server        │     │    │
│  │  │  - Port 3002            │     │    │
│  │  │  - JWT auth             │     │    │
│  │  └──────────────────────────┘     │    │
│  │                                    │    │
│  │  ┌──────────────────────────┐     │    │
│  │  │  SQLite DB (Volume)      │     │    │
│  │  │  - WAL mode              │     │    │
│  │  │  - Better-sqlite3        │     │    │
│  │  └──────────────────────────┘     │    │
│  └────────────────────────────────────┘    │
│                                             │
│  NGINX Reverse Proxy                        │
│  - api-pantrypal.subasically.me            │
│  - SSL via Let's Encrypt                   │
└─────────────────────────────────────────────┘
         ↑
         │ HTTPS
         │
    ┌────────┐
    │ iOS App │
    └────────┘
```

**Limitations:**
- Single point of failure (no redundancy)
- No auto-scaling
- Manual backups
- Limited monitoring
- ~99.9% uptime SLA
- Complex manual deployment
- No load balancing
- SQLite limits concurrent writes

---

## Proposed AWS Architecture (Production-Ready MVP)

```
                    ┌──────────────────────────────────────────┐
                    │          Route 53 (DNS)                  │
                    │  api-pantrypal.subasically.me            │
                    └──────────────┬───────────────────────────┘
                                   │
                    ┌──────────────▼───────────────────────────┐
                    │   Application Load Balancer (ALB)        │
                    │   - SSL Termination (ACM Certificate)   │
                    │   - Health checks                        │
                    │   - Auto-scaling trigger                 │
                    └──────────────┬───────────────────────────┘
                                   │
            ┌──────────────────────┴──────────────────────┐
            │                                             │
┌───────────▼───────────┐                   ┌─────────────▼────────────┐
│   ECS Fargate         │                   │   ECS Fargate            │
│   (Node.js API)       │                   │   (Node.js API)          │
│   - Container 1       │                   │   - Container 2          │
│   - Auto-scaling      │                   │   - Auto-scaling         │
│   - 0.5 vCPU / 1GB    │                   │   - 0.5 vCPU / 1GB       │
└───────────┬───────────┘                   └─────────────┬────────────┘
            │                                             │
            └──────────────────┬──────────────────────────┘
                               │
                ┌──────────────▼────────────────┐
                │   RDS PostgreSQL              │
                │   - db.t4g.micro (Free Tier) │
                │   - Multi-AZ (HA)             │
                │   - Automated backups         │
                │   - 20GB storage              │
                └───────────────────────────────┘

        ┌───────────────────────────────────────┐
        │   CloudWatch Logs & Metrics           │
        │   - API request logs                  │
        │   - Error tracking                    │
        │   - Performance metrics               │
        │   - Alarms (error rate, latency)      │
        └───────────────────────────────────────┘

        ┌───────────────────────────────────────┐
        │   S3 Bucket                           │
        │   - Database backups                  │
        │   - Future: Receipt images            │
        │   - Versioning enabled                │
        └───────────────────────────────────────┘

        ┌───────────────────────────────────────┐
        │   Secrets Manager                     │
        │   - JWT_SECRET                        │
        │   - DB credentials                    │
        │   - Apple Sign In keys                │
        └───────────────────────────────────────┘
```

---

## Service Selection & Rationale

### 1. **ECS Fargate** (Compute)
**Why:** Serverless containers - no EC2 management, pay only for what you use

**Alternatives Considered:**
- ❌ **EC2**: Requires OS maintenance, over-provisioning, 24/7 billing
- ❌ **Lambda**: Cold starts hurt UX, 15min timeout, complex for Express apps
- ❌ **App Runner**: Limited control, newer service, harder debugging
- ❌ **Elastic Beanstalk**: Legacy, abstraction hides AWS features

**Configuration:**
```yaml
Task Definition:
  CPU: 0.5 vCPU (512 units)
  Memory: 1 GB
  Container:
    Image: <your-ecr-repo>/pantrypal-api:latest
    Port: 3002
    Environment:
      - NODE_ENV=production
      - PORT=3002
    Secrets (from Secrets Manager):
      - JWT_SECRET
      - DB_HOST
      - DB_PASSWORD
```

**Scaling Policy:**
- Min: 1 task (always running)
- Max: 4 tasks (handles spikes)
- Target CPU: 70%
- Target Memory: 80%

**Cost:** ~$15-30/month (1-2 tasks running 24/7)

---

### 2. **RDS PostgreSQL** (Database)
**Why:** Managed, reliable, auto-backups, scalable, better concurrency than SQLite

**Configuration:**
```yaml
Instance: db.t4g.micro (Free Tier eligible - 1 year)
Engine: PostgreSQL 16
Storage: 20 GB SSD (gp3)
Multi-AZ: Yes (high availability)
Backup: 7-day retention, daily snapshots
Encryption: Yes (at rest and in transit)
```

**Migration from SQLite:**
1. Export SQLite schema → PostgreSQL DDL
2. Use `pgloader` or custom Node.js script to migrate data
3. Update `better-sqlite3` → `pg` (node-postgres) in codebase
4. Test locally with PostgreSQL Docker container

**Cost:** 
- Free Tier (12 months): $0
- After: ~$15-20/month (t4g.micro)

---

### 3. **Application Load Balancer** (ALB)
**Why:** Health checks, SSL termination, multi-AZ, WebSocket support

**Configuration:**
```yaml
Scheme: Internet-facing
Listeners:
  - Port 443 (HTTPS)
    Certificate: ACM (auto-renewed)
    Target: ECS Fargate tasks
  - Port 80 (HTTP)
    Redirect to HTTPS
    
Health Check:
  Path: /health
  Interval: 30s
  Timeout: 5s
  Healthy threshold: 2
  Unhealthy threshold: 3
```

**Cost:** ~$16/month + $0.008/GB data transfer

---

### 4. **CloudWatch** (Monitoring & Logging)
**Why:** Centralized logs, metrics, alarms - critical for production debugging

**Configuration:**
```yaml
Log Groups:
  - /ecs/pantrypal-api (retention: 7 days)
  
Metrics:
  - API request count
  - Error rate (5xx)
  - Response time (p50, p95, p99)
  - ECS CPU/Memory utilization
  - RDS connections
  
Alarms:
  - Error rate > 5% → Email + Slack
  - RDS CPU > 80% → Scale up warning
  - ECS task unhealthy → Auto-restart
```

**Cost:** ~$5-10/month (depending on log volume)

---

### 5. **S3** (Backups & Future Assets)
**Why:** Durable storage (99.999999999%), cheap, versioning

**Configuration:**
```yaml
Bucket: pantrypal-backups
Versioning: Enabled
Lifecycle Rules:
  - Delete backups > 30 days old
Encryption: AES-256
```

**Cost:** ~$1-3/month (first GB free, backups are small)

---

### 6. **Secrets Manager**
**Why:** Secure credential storage, auto-rotation, audit logs

**Secrets:**
- `pantrypal/prod/jwt-secret`
- `pantrypal/prod/db-credentials`
- `pantrypal/prod/apple-signin`

**Cost:** $0.40/secret/month (~$1.20/month total)

---

### 7. **Route 53** (DNS)
**Why:** AWS-native, health checks, failover support

**Configuration:**
```yaml
Hosted Zone: subasically.me
Record: api-pantrypal.subasically.me
Type: A (Alias to ALB)
Routing: Simple (no geo/latency routing needed for MVP)
```

**Cost:** $0.50/month (hosted zone)

---

## Total Cost Estimate

### Free Tier (First 12 Months):
| Service | Cost |
|---------|------|
| ECS Fargate | ~$20/month (1-2 tasks) |
| RDS (t4g.micro) | **$0** (Free Tier) |
| ALB | ~$16/month |
| CloudWatch | ~$5/month |
| S3 | ~$1/month |
| Secrets Manager | ~$1/month |
| Route 53 | ~$0.50/month |
| **Total** | **~$43.50/month** |

### After Free Tier (Year 2+):
| Service | Cost |
|---------|------|
| ECS Fargate | ~$20/month |
| RDS (t4g.micro) | ~$15/month |
| ALB | ~$16/month |
| CloudWatch | ~$5/month |
| S3 | ~$1/month |
| Secrets Manager | ~$1/month |
| Route 53 | ~$0.50/month |
| **Total** | **~$58.50/month** |

**Comparison to Contabo:**
- Contabo VPS: ~$10/month (but requires manual management, no HA)
- AWS: ~$43.50/month (with auto-scaling, backups, monitoring, 99.99% SLA)
- **Worth it:** Yes, for production reliability and scale

---

## Migration Steps (Detailed)

### **Phase 1: Setup AWS Infrastructure (Day 1-2)**

1. **Create VPC & Networking**
   ```bash
   # Use default VPC or create custom:
   - VPC: 10.0.0.0/16
   - Public Subnets: 2 (for ALB)
   - Private Subnets: 2 (for ECS tasks, RDS)
   - NAT Gateway: 1 (for ECS outbound, e.g., UPC API)
   - Internet Gateway: 1
   ```

2. **Set up RDS PostgreSQL**
   ```bash
   # Console or CLI:
   aws rds create-db-instance \
     --db-instance-identifier pantrypal-prod \
     --db-instance-class db.t4g.micro \
     --engine postgres \
     --master-username admin \
     --master-user-password <strong-password> \
     --allocated-storage 20 \
     --multi-az \
     --backup-retention-period 7 \
     --vpc-security-group-ids sg-xxx \
     --db-subnet-group-name pantrypal-subnet-group
   ```

3. **Create ECR Repository**
   ```bash
   aws ecr create-repository --repository-name pantrypal-api
   ```

4. **Store Secrets in Secrets Manager**
   ```bash
   aws secretsmanager create-secret \
     --name pantrypal/prod/jwt-secret \
     --secret-string '{"JWT_SECRET":"your-secret-here"}'
   
   aws secretsmanager create-secret \
     --name pantrypal/prod/db-credentials \
     --secret-string '{"username":"admin","password":"xxx","host":"xxx.rds.amazonaws.com","database":"pantrypal"}'
   ```

5. **Create S3 Bucket**
   ```bash
   aws s3 mb s3://pantrypal-backups
   aws s3api put-bucket-versioning \
     --bucket pantrypal-backups \
     --versioning-configuration Status=Enabled
   ```

---

### **Phase 2: Migrate Database (Day 3)**

1. **Export SQLite Data**
   ```bash
   # On Contabo server:
   ssh root@62.146.177.62
   cd /root/pantrypal-server
   docker-compose exec pantrypal-api sqlite3 /app/db/pantrypal.db .dump > backup.sql
   ```

2. **Convert SQLite → PostgreSQL Schema**
   ```sql
   -- Replace SQLite-specific syntax:
   -- AUTOINCREMENT → SERIAL
   -- datetime('now') → NOW()
   -- TEXT → VARCHAR or TEXT
   -- INTEGER PRIMARY KEY → SERIAL PRIMARY KEY
   
   -- See server/db/schema-postgres.sql (create this file)
   ```

3. **Create Migration Script**
   ```javascript
   // server/scripts/migrate-to-postgres.js
   const sqlite = require('better-sqlite3');
   const { Pool } = require('pg');
   
   const sqliteDb = new sqlite('./backup.db');
   const pgPool = new Pool({
     host: process.env.DB_HOST,
     user: process.env.DB_USER,
     password: process.env.DB_PASSWORD,
     database: 'pantrypal'
   });
   
   async function migrate() {
     // Read from SQLite, insert into PostgreSQL
     // Handle UUIDs, timestamps, etc.
   }
   ```

4. **Test Locally**
   ```bash
   # Run PostgreSQL in Docker
   docker run -d --name postgres-test \
     -e POSTGRES_PASSWORD=test \
     -e POSTGRES_DB=pantrypal \
     -p 5432:5432 \
     postgres:16
   
   # Test migration
   node server/scripts/migrate-to-postgres.js
   
   # Run API locally against PostgreSQL
   npm run dev
   ```

---

### **Phase 3: Containerize & Deploy (Day 4)**

1. **Update Dockerfile for Production**
   ```dockerfile
   # server/Dockerfile
   FROM node:20-alpine
   
   WORKDIR /app
   
   # Install dependencies
   COPY package*.json ./
   RUN npm ci --only=production
   
   # Copy source
   COPY . .
   
   # Health check
   HEALTHCHECK --interval=30s --timeout=3s --start-period=10s \
     CMD node -e "require('http').get('http://localhost:3002/health', (r) => {process.exit(r.statusCode === 200 ? 0 : 1)})"
   
   EXPOSE 3002
   CMD ["node", "src/index.js"]
   ```

2. **Build & Push to ECR**
   ```bash
   # Login to ECR
   aws ecr get-login-password --region us-east-1 | \
     docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com
   
   # Build image
   cd server
   docker build -t pantrypal-api .
   docker tag pantrypal-api:latest <account-id>.dkr.ecr.us-east-1.amazonaws.com/pantrypal-api:latest
   
   # Push
   docker push <account-id>.dkr.ecr.us-east-1.amazonaws.com/pantrypal-api:latest
   ```

3. **Create ECS Task Definition**
   ```json
   {
     "family": "pantrypal-api",
     "networkMode": "awsvpc",
     "requiresCompatibilities": ["FARGATE"],
     "cpu": "512",
     "memory": "1024",
     "containerDefinitions": [{
       "name": "api",
       "image": "<account-id>.dkr.ecr.us-east-1.amazonaws.com/pantrypal-api:latest",
       "portMappings": [{"containerPort": 3002}],
       "secrets": [
         {"name": "JWT_SECRET", "valueFrom": "arn:aws:secretsmanager:..."},
         {"name": "DB_HOST", "valueFrom": "arn:aws:secretsmanager:..."}
       ],
       "logConfiguration": {
         "logDriver": "awslogs",
         "options": {
           "awslogs-group": "/ecs/pantrypal-api",
           "awslogs-region": "us-east-1",
           "awslogs-stream-prefix": "ecs"
         }
       }
     }]
   }
   ```

4. **Create ECS Service**
   ```bash
   aws ecs create-service \
     --cluster pantrypal-cluster \
     --service-name pantrypal-api \
     --task-definition pantrypal-api:1 \
     --desired-count 1 \
     --launch-type FARGATE \
     --network-configuration "awsvpcConfiguration={subnets=[subnet-xxx],securityGroups=[sg-xxx],assignPublicIp=ENABLED}" \
     --load-balancers "targetGroupArn=arn:aws:elasticloadbalancing:...,containerName=api,containerPort=3002"
   ```

5. **Create ALB & Target Group**
   ```bash
   # Create ALB
   aws elbv2 create-load-balancer \
     --name pantrypal-alb \
     --subnets subnet-xxx subnet-yyy \
     --security-groups sg-xxx
   
   # Create Target Group
   aws elbv2 create-target-group \
     --name pantrypal-api-tg \
     --protocol HTTP \
     --port 3002 \
     --vpc-id vpc-xxx \
     --target-type ip \
     --health-check-path /health
   
   # Create Listener
   aws elbv2 create-listener \
     --load-balancer-arn arn:aws:elasticloadbalancing:... \
     --protocol HTTPS \
     --port 443 \
     --certificates CertificateArn=arn:aws:acm:... \
     --default-actions Type=forward,TargetGroupArn=arn:aws:elasticloadbalancing:...
   ```

---

### **Phase 4: DNS & SSL (Day 5)**

1. **Request ACM Certificate**
   ```bash
   aws acm request-certificate \
     --domain-name api-pantrypal.subasically.me \
     --validation-method DNS
   
   # Add CNAME records to Route 53 for validation
   ```

2. **Update Route 53**
   ```bash
   aws route53 change-resource-record-sets \
     --hosted-zone-id Z... \
     --change-batch '{
       "Changes": [{
         "Action": "UPSERT",
         "ResourceRecordSet": {
           "Name": "api-pantrypal.subasically.me",
           "Type": "A",
           "AliasTarget": {
             "HostedZoneId": "Z...",
             "DNSName": "pantrypal-alb-xxx.us-east-1.elb.amazonaws.com",
             "EvaluateTargetHealth": true
           }
         }
       }]
     }'
   ```

---

### **Phase 5: Testing & Cutover (Day 6-7)**

1. **Test AWS Deployment**
   ```bash
   # Verify health
   curl https://api-pantrypal.subasically.me/health
   
   # Test auth
   curl -X POST https://api-pantrypal.subasically.me/api/auth/login \
     -H "Content-Type: application/json" \
     -d '{"email":"test@example.com","password":"xxx"}'
   
   # Test inventory
   # ... etc
   ```

2. **Update iOS App (if needed)**
   ```swift
   // ios/PantryPal/Services/APIService.swift
   // No change needed if using same domain!
   // DNS handles the cutover automatically
   ```

3. **Monitor CloudWatch**
   ```bash
   # Watch logs in real-time
   aws logs tail /ecs/pantrypal-api --follow
   
   # Check metrics
   # Console → CloudWatch → Metrics → ECS/RDS
   ```

4. **Gradual Cutover**
   ```bash
   # Option 1: DNS cutover (instant)
   # Update Route 53 A record to point to ALB
   
   # Option 2: Staged (safer)
   # Keep Contabo running for 1 week
   # Monitor AWS for issues
   # If all good, shut down Contabo
   ```

---

### **Phase 6: Cleanup & Optimization (Day 8-14)**

1. **Set up Auto-Scaling**
   ```bash
   aws application-autoscaling register-scalable-target \
     --service-namespace ecs \
     --resource-id service/pantrypal-cluster/pantrypal-api \
     --scalable-dimension ecs:service:DesiredCount \
     --min-capacity 1 \
     --max-capacity 4
   
   aws application-autoscaling put-scaling-policy \
     --policy-name cpu-scaling \
     --service-namespace ecs \
     --resource-id service/pantrypal-cluster/pantrypal-api \
     --scalable-dimension ecs:service:DesiredCount \
     --policy-type TargetTrackingScaling \
     --target-tracking-scaling-policy-configuration '{
       "TargetValue": 70.0,
       "PredefinedMetricSpecification": {
         "PredefinedMetricType": "ECSServiceAverageCPUUtilization"
       }
     }'
   ```

2. **Set up CloudWatch Alarms**
   ```bash
   aws cloudwatch put-metric-alarm \
     --alarm-name pantrypal-high-error-rate \
     --comparison-operator GreaterThanThreshold \
     --evaluation-periods 2 \
     --metric-name 5xxError \
     --namespace AWS/ApplicationELB \
     --period 60 \
     --statistic Sum \
     --threshold 10 \
     --alarm-actions arn:aws:sns:us-east-1:xxx:alerts
   ```

3. **Automated Backups**
   ```bash
   # RDS automated backups (already enabled)
   # + Manual S3 backup script:
   
   # server/scripts/backup-to-s3.js
   const { exec } = require('child_process');
   const AWS = require('aws-sdk');
   const s3 = new AWS.S3();
   
   // Backup RDS snapshot to S3
   // Run daily via CloudWatch Events (EventBridge)
   ```

4. **Decommission Contabo**
   ```bash
   # After 1 week of stable AWS operation:
   ssh root@62.146.177.62
   docker-compose down -v
   # Cancel Contabo subscription
   ```

---

## Code Changes Required

### 1. **Update Database Client** (`server/src/models/database.js`)

```javascript
// BEFORE (SQLite):
const Database = require('better-sqlite3');
const db = new Database('./db/pantrypal.db');

// AFTER (PostgreSQL):
const { Pool } = require('pg');
const pool = new Pool({
    host: process.env.DB_HOST,
    port: process.env.DB_PORT || 5432,
    database: process.env.DB_NAME || 'pantrypal',
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    ssl: { rejectUnauthorized: false } // For RDS
});

// Wrapper for sync-like interface (or refactor to async)
module.exports = pool;
```

### 2. **Update SQL Queries**

```javascript
// BEFORE (SQLite):
db.prepare('SELECT * FROM users WHERE id = ?').get(userId);

// AFTER (PostgreSQL):
const result = await pool.query('SELECT * FROM users WHERE id = $1', [userId]);
const user = result.rows[0];
```

### 3. **Update Environment Variables**

```bash
# BEFORE (.env):
JWT_SECRET=xxx
PORT=3002

# AFTER (ECS Task Definition secrets):
JWT_SECRET=xxx (from Secrets Manager)
DB_HOST=xxx.rds.amazonaws.com (from Secrets Manager)
DB_USER=admin
DB_PASSWORD=xxx
DB_NAME=pantrypal
PORT=3002
NODE_ENV=production
```

### 4. **Add Health Check Endpoint** (`server/src/routes/health.js`)

```javascript
// server/src/app.js
app.get('/health', async (req, res) => {
    try {
        // Check DB connection
        await pool.query('SELECT 1');
        res.json({ status: 'healthy', timestamp: new Date().toISOString() });
    } catch (error) {
        res.status(503).json({ status: 'unhealthy', error: error.message });
    }
});
```

---

## Rollback Plan

If AWS deployment fails:

1. **Keep Contabo Running** during migration (parallel deployment)
2. **DNS Rollback**: Update Route 53 A record back to Contabo IP (62.146.177.62)
3. **TTL**: Set TTL to 60s during migration for fast rollback
4. **Data Sync**: If users created data on AWS during testing, manually export and import back to SQLite

---

## Benefits of AWS Migration

| Feature | Contabo VPS | AWS |
|---------|-------------|-----|
| **Uptime SLA** | ~99.9% (no guarantee) | 99.99% (ALB + Multi-AZ RDS) |
| **Auto-Scaling** | ❌ Manual | ✅ Automatic (CPU/Memory triggers) |
| **Backups** | ❌ Manual scripts | ✅ Automated (RDS snapshots + S3) |
| **Monitoring** | ❌ Basic logs | ✅ CloudWatch (metrics, alarms, logs) |
| **SSL Management** | ❌ Manual (Let's Encrypt) | ✅ Automatic (ACM auto-renewal) |
| **Load Balancing** | ❌ Single instance | ✅ ALB across multiple AZs |
| **Database** | SQLite (single writer) | PostgreSQL (concurrent writes, ACID) |
| **Security** | ❌ Manual patches | ✅ Managed (RDS, Fargate patching) |
| **Cost** | $10/month | $43.50/month (Free Tier) / $58.50/month (after) |
| **Deployment** | ❌ Manual SCP + SSH | ✅ CI/CD (GitHub Actions → ECR → ECS) |
| **Compliance** | ❌ DIY | ✅ SOC 2, GDPR, HIPAA-eligible |

---

## Timeline Summary

| Phase | Duration | Tasks |
|-------|----------|-------|
| **Phase 1** | 1-2 days | Setup VPC, RDS, ECR, S3, Secrets Manager |
| **Phase 2** | 1 day | Export SQLite, convert to PostgreSQL, test locally |
| **Phase 3** | 1 day | Build Docker image, deploy to ECS, configure ALB |
| **Phase 4** | 1 day | Request ACM cert, update DNS |
| **Phase 5** | 2 days | End-to-end testing, gradual cutover |
| **Phase 6** | 1 week | Monitor, optimize, cleanup Contabo |
| **Total** | **~2 weeks** | Safe, tested migration |

---

## Next Steps

1. ✅ **Fix Location Bug** (deploy householdService.js update)
2. ✅ **Reset Database** (delete duplicate locations)
3. ⏳ **Finish TestFlight Testing** (validate all features work)
4. ⏳ **AWS Account Setup** (if not already done)
5. ⏳ **Phase 1: Infrastructure** (VPC, RDS, ECR)
6. ⏳ **Phase 2: Database Migration** (SQLite → PostgreSQL)
7. ⏳ **Phase 3: Deploy to ECS** (parallel to Contabo)
8. ⏳ **Phase 4: DNS Cutover** (after 48hrs of stable AWS operation)
9. ⏳ **Phase 5: Decommission Contabo** (1 week after cutover)

---

## Questions?

- **When to migrate?** After TestFlight, before App Store launch
- **How long will migration take?** 1-2 weeks (careful, tested)
- **Will app be down?** No - parallel deployment, DNS cutover
- **What if something breaks?** DNS rollback to Contabo (< 5min)
- **Cost concern?** $43.50/month is reasonable for production-grade infrastructure

**Recommendation:** Start Phase 1 (infrastructure setup) now, complete migration before App Store submission. This gives time to test under production load without user impact.
