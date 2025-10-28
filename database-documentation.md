# Database Schema Documentation

## Overview

This PostgreSQL database schema is designed for an intelligent bookkeeping system that integrates Dext (receipt capture), Claude AI (intelligent processing), QuickBooks (accounting), and Xenett (quality control).

**Key Design Principles:**
- **Immutability**: Data is never deleted, only archived
- **Complete Audit Trail**: Every change is logged with reasoning
- **Performance**: Indexed for common queries, partitioned for scale
- **Learning**: System improves over time through Claude learnings table
- **Compliance**: 7-year audit retention with full traceability

## Entity Relationship Diagram

```
┌─────────────────┐
│   companies     │
│─────────────────│
│ id (PK)         │────┐
│ name            │    │
│ qb_realm_id     │    │
│ settings (JSON) │    │
└─────────────────┘    │
                       │
        ┌──────────────┴──────────────────────────────────┐
        │                                                  │
        │                                                  │
┌───────▼──────┐  ┌──────────────┐  ┌──────────────┐  ┌──▼──────────┐
│    users     │  │   vendors    │  │ chart_of_    │  │  documents  │
│──────────────│  │──────────────│  │  accounts    │  │─────────────│
│ id (PK)      │  │ id (PK)      │  │──────────────│  │ id (PK)     │
│ company_id   │  │ company_id   │  │ id (PK)      │  │ company_id  │
│ email        │  │ name         │  │ company_id   │  │ source      │
│ role         │  │ qb_vendor_id │  │ qb_acct_id   │  │ doc_type    │
│ expense_limit│  │ typical_cats │  │ account_name │  │ storage_url │
└──────┬───────┘  └──────┬───────┘  │ keywords     │  │ submitted_by│
       │                 │          └──────┬───────┘  │ status      │
       │                 │                 │          └──────┬──────┘
       │                 │                 │                 │
       │          ┌──────▼─────────────────▼────┐           │
       │          │      transactions            │◄──────────┤
       │          │──────────────────────────────│           │
       │          │ id (PK)                      │           │
       │          │ company_id                   │           │
       │          │ document_id (FK)             │           │
       │          │ vendor_id (FK)               │           │
       │          │ gl_account_id (FK)           │           │
       │          │ amount_cents                 │           │
       │          │ category                     │           │
       │          │ is_split                     │           │
       │          │ parent_transaction_id (FK)   │◄──┐       │
       │          └────────┬──────────────────┬──┘   │       │
       │                   │                  │      │       │
       │                   │                  └──────┘       │
       │                   │                                 │
       │          ┌────────▼────────────────────┐            │
       │          │   processing_events         │◄───────────┤
       │          │─────────────────────────────│            │
       │          │ id (PK)                     │            │
       │          │ document_id (FK)            │            │
       │          │ transaction_id (FK)         │            │
       │          │ agent_name                  │            │
       │          │ stage                       │            │
       │          │ input_data (JSON)           │            │
       │          │ output_data (JSON)          │            │
       │          │ confidence_score            │            │
       │          │ reasoning                   │            │
       │          └─────────────────────────────┘            │
       │                                                     │
       │          ┌─────────────────────────────┐            │
       │          │     user_queries            │◄───────────┤
       │          │─────────────────────────────│            │
       ├──────────┤ id (PK)                     │            │
       │          │ document_id (FK)            │            │
       │          │ asked_to_user_id (FK)       │◄───────────┤
       │          │ question_text               │            │
       │          │ response_text               │            │
       │          │ responded_at                │            │
       │          └─────────────────────────────┘            │
       │                                                     │
       │          ┌─────────────────────────────┐            │
       │          │       approvals             │◄───────────┤
       │          │─────────────────────────────│            │
       ├──────────┤ id (PK)                     │            │
       │          │ document_id (FK)            │            │
       ├──────────┤ assigned_to_user_id (FK)    │◄───────────┤
       │          ├ decided_by_user_id (FK)     │            │
       │          │ approval_type               │            │
       │          │ decision                    │            │
       │          │ modifications (JSON)        │            │
       │          └─────────────────────────────┘            │
       │                                                     │
       │          ┌──────────────────────────────┐           │
       │          │  quickbooks_transactions     │◄──────────┤
       │          │──────────────────────────────│           │
       ├──────────┤ id (PK)                      │           │
       │          │ document_id (FK)             │           │
       │          │ transaction_id (FK)          │           │
       │          │ qb_transaction_id            │           │
       │          │ posted_by_user_id (FK)       │◄──────────┤
       │          │ qb_request_payload (JSON)    │           │
       │          │ qb_response_payload (JSON)   │           │
       │          │ is_reversed                  │           │
       │          └──────────┬───────────────────┘           │
       │                     │                               │
       │          ┌──────────▼───────────────────┐           │
       │          │   xenett_validations         │           │
       │          │──────────────────────────────│           │
       ├──────────┤ id (PK)                      │           │
       │          │ qb_transaction_id (FK)       │           │
       │          │ validation_status            │           │
       │          │ errors_found (JSON)          │           │
       │          │ resolved_by_user_id (FK)     │◄──────────┘
       │          └──────────────────────────────┘
       │
       │          ┌──────────────────────────────┐
       │          │     claude_learnings         │
       │          │──────────────────────────────│
       │          │ id (PK)                      │
       │          │ company_id (FK)              │
       │          │ learning_type                │
       │          │ pattern                      │
       │          │ rule (JSON)                  │
       │          │ times_applied                │
       │          │ times_correct                │
       │          │ current_confidence           │
       │          └──────────────────────────────┘
       │
       │          ┌──────────────────────────────┐
       └──────────┤        audit_log             │
                  │──────────────────────────────│
                  │ id (PK)                      │
                  │ company_id (FK)              │
                  │ event_type                   │
                  │ entity_type                  │
                  │ entity_id                    │
                  │ actor_type                   │
                  │ actor_id                     │
                  │ changes (JSON)               │
                  │ occurred_at                  │
                  └──────────────────────────────┘
                         (IMMUTABLE)
```

## Table Groups

### 1. Core Domain Tables

#### companies
Master table for businesses using the system (supports multi-tenant).

**Key Fields:**
- `quickbooks_realm_id`: Unique QB company identifier
- `settings`: JSON blob for company-specific rules, GL mappings, policies
- `fiscal_year_end`: For proper period reporting

**Usage:**
```sql
-- Get active companies
SELECT * FROM companies WHERE status = 'active';

-- Get company with settings
SELECT name, settings->>'expense_approval_threshold'
FROM companies WHERE id = 'uuid';
```

#### users
Employees, managers, accountants who interact with the system.

**Key Fields:**
- `role`: Determines approval authority and expense limits
- `single_transaction_limit`: Max $ per transaction (in cents)
- `notification_preferences`: How to contact for queries/approvals

**Usage:**
```sql
-- Find users who need to approve $2500 expense
SELECT * FROM users
WHERE company_id = 'uuid'
  AND single_transaction_limit >= 250000
  AND role IN ('manager', 'director', 'vp')
  AND status = 'active';
```

#### vendors
Enriched vendor data beyond what's in QuickBooks.

**Key Fields:**
- `name_normalized`: Used for fuzzy matching (lowercase, alphanumeric only)
- `typical_categories`: Learned over time from transactions
- `processing_notes`: Historical context from Claude agents

**Usage:**
```sql
-- Fuzzy vendor search
SELECT * FROM vendors
WHERE company_id = 'uuid'
  AND similarity(name_normalized, 'amzn') > 0.8
ORDER BY similarity(name_normalized, 'amzn') DESC;

-- Get vendor spending pattern
SELECT
  name,
  typical_categories,
  average_transaction_amount::FLOAT / 100 as avg_amount
FROM vendors
WHERE company_id = 'uuid'
ORDER BY average_transaction_amount DESC;
```

#### chart_of_accounts
Cached QuickBooks chart of accounts with AI enhancements.

**Key Fields:**
- `keywords`: Words that suggest this GL account (for auto-categorization)
- `typical_vendors`: Vendors that usually use this account
- `last_synced_from_qb`: Track freshness

**Usage:**
```sql
-- Find GL account by keyword
SELECT account_number, account_name
FROM chart_of_accounts
WHERE company_id = 'uuid'
  AND 'office' = ANY(keywords)
  AND is_active = true;
```

### 2. Document & Transaction Tables

#### documents
Source documents from Dext or manual upload.

**Partitioned by month** for performance.

**Key Fields:**
- `source_id`: Dext document ID for linking
- `ocr_text`: Full text for full-text search
- `status`: Tracks workflow state

**Workflow States:**
- `pending`: Just uploaded
- `processing`: Claude agents working on it
- `needs_review`: Low confidence or policy issue
- `approved`: Ready for QB posting
- `posted`: Successfully in QuickBooks
- `rejected`: Will not be posted

**Usage:**
```sql
-- Full-text search across documents
SELECT id, document_type, document_date
FROM documents
WHERE company_id = 'uuid'
  AND to_tsvector('english', ocr_text) @@ to_tsquery('office & supplies');

-- Documents awaiting posting
SELECT * FROM documents
WHERE status = 'approved'
  AND NOT EXISTS (
    SELECT 1 FROM quickbooks_transactions qbt
    WHERE qbt.document_id = documents.id
  );
```

#### transactions
Extracted transaction data, enhanced by Claude.

**Key Fields:**
- `amount_cents`: Always store as integers to avoid float errors
- `is_split`: Parent transaction split across categories/departments
- `parent_transaction_id`: Self-reference for split transactions
- `line_items`: JSON array of detailed receipt items

**Usage:**
```sql
-- Get split transaction with all parts
WITH RECURSIVE split_parts AS (
  SELECT * FROM transactions WHERE id = 'parent_uuid'
  UNION ALL
  SELECT t.* FROM transactions t
  INNER JOIN split_parts sp ON t.parent_transaction_id = sp.id
)
SELECT * FROM split_parts;

-- Monthly spending by category
SELECT
  category,
  SUM(amount_cents)::FLOAT / 100 as total_spent,
  COUNT(*) as transaction_count
FROM transactions
WHERE company_id = 'uuid'
  AND transaction_date >= DATE_TRUNC('month', CURRENT_DATE)
GROUP BY category
ORDER BY total_spent DESC;
```

### 3. Claude Processing Tables

#### processing_events
Every step of Claude's processing, logged.

**Partitioned by month** for performance.

**Key Fields:**
- `agent_name`: Which subagent ran (context-analyzer, policy-enforcer, etc.)
- `stage`: Where in pipeline (extraction, validation, posting, etc.)
- `confidence_score`: 0.00-1.00, drives human-in-loop decisions
- `reasoning`: Claude's explanation (critical for audit)

**Usage:**
```sql
-- Find low-confidence decisions
SELECT
  d.document_type,
  pe.agent_name,
  pe.confidence_score,
  pe.reasoning
FROM processing_events pe
JOIN documents d ON pe.document_id = d.id
WHERE pe.confidence_score < 0.70
  AND pe.created_at > NOW() - INTERVAL '7 days'
ORDER BY pe.confidence_score;

-- Average confidence by agent
SELECT
  agent_name,
  AVG(confidence_score) as avg_confidence,
  COUNT(*) as decisions_made
FROM processing_events
WHERE company_id = 'uuid'
  AND created_at > NOW() - INTERVAL '30 days'
GROUP BY agent_name
ORDER BY avg_confidence DESC;
```

#### claude_learnings
Machine learning improvements over time.

**Key Fields:**
- `learning_type`: What kind of pattern (vendor_category, gl_mapping, etc.)
- `rule`: Structured JSON that can be applied programmatically
- `times_correct` / `times_corrected`: Validation metrics
- `current_confidence`: Updated as rule is validated in production

**Usage:**
```sql
-- Get high-confidence learnings for vendor categorization
SELECT
  pattern,
  rule,
  current_confidence,
  times_applied
FROM claude_learnings
WHERE company_id = 'uuid'
  AND learning_type = 'vendor_category'
  AND current_confidence > 0.90
  AND status = 'active'
ORDER BY current_confidence DESC;

-- Track learning accuracy over time
SELECT
  learning_type,
  AVG(times_correct::FLOAT / NULLIF(times_applied, 0)) as accuracy,
  COUNT(*) as total_learnings
FROM claude_learnings
WHERE company_id = 'uuid'
  AND status = 'active'
GROUP BY learning_type;
```

### 4. Human Interaction Tables

#### user_queries
When Claude needs to ask users for clarification.

**Key Fields:**
- `question_type`: Categorizes the kind of question
- `response_structured`: Parsed response (not just raw text)
- `response_time_seconds`: Track how long users take to respond

**Usage:**
```sql
-- Unanswered questions older than 24 hours
SELECT
  uq.question_text,
  d.document_type,
  u.full_name,
  uq.asked_at
FROM user_queries uq
JOIN documents d ON uq.document_id = d.id
JOIN users u ON uq.asked_to_user_id = u.id
WHERE uq.responded_at IS NULL
  AND uq.asked_at < NOW() - INTERVAL '24 hours'
ORDER BY uq.asked_at;

-- Average response time by user
SELECT
  u.full_name,
  AVG(uq.response_time_seconds) / 60 as avg_response_minutes,
  COUNT(*) as questions_answered
FROM user_queries uq
JOIN users u ON uq.asked_to_user_id = u.id
WHERE uq.responded_at IS NOT NULL
  AND uq.asked_at > NOW() - INTERVAL '30 days'
GROUP BY u.full_name
ORDER BY avg_response_minutes;
```

#### approvals
Approval workflow tracking for policy exceptions and high-value items.

**Key Fields:**
- `approval_type`: Why approval needed (amount_threshold, policy_exception, etc.)
- `modifications`: If approver changed the transaction data
- `escalated_from_user_id`: If escalated up the chain

**Usage:**
```sql
-- Pending approvals assigned to user
SELECT
  d.document_type,
  t.amount_cents::FLOAT / 100 as amount,
  t.vendor_name_raw,
  a.approval_reason,
  a.requested_at
FROM approvals a
JOIN documents d ON a.document_id = d.id
JOIN transactions t ON a.transaction_id = t.id
WHERE a.assigned_to_user_id = 'user_uuid'
  AND a.decision IS NULL
ORDER BY a.requested_at;

-- Approval metrics by type
SELECT
  approval_type,
  COUNT(*) as total_requests,
  COUNT(*) FILTER (WHERE decision = 'approved') as approved,
  COUNT(*) FILTER (WHERE decision = 'rejected') as rejected,
  AVG(EXTRACT(EPOCH FROM (decided_at - requested_at))) / 3600 as avg_hours_to_decide
FROM approvals
WHERE company_id = 'uuid'
  AND requested_at > NOW() - INTERVAL '90 days'
GROUP BY approval_type;
```

### 5. QuickBooks Integration Tables

#### quickbooks_transactions
Successfully posted transactions in QuickBooks.

**Key Fields:**
- `quickbooks_transaction_id`: QB's ID for the transaction
- `qb_sync_token`: Required for updates to QB transactions
- `is_reversed`: Track if transaction was reversed
- `reversal_transaction_id`: Links to the reversal entry

**Usage:**
```sql
-- Transactions posted today
SELECT
  qbt.quickbooks_transaction_type,
  t.vendor_name_raw,
  t.amount_cents::FLOAT / 100 as amount,
  u.full_name as posted_by
FROM quickbooks_transactions qbt
JOIN transactions t ON qbt.transaction_id = t.id
JOIN users u ON qbt.posted_by_user_id = u.id
WHERE qbt.posted_at::DATE = CURRENT_DATE
ORDER BY qbt.posted_at DESC;

-- Failed postings (documents approved but not in QB)
SELECT
  d.id,
  d.document_type,
  d.status,
  d.submitted_at
FROM documents d
WHERE d.status = 'approved'
  AND NOT EXISTS (
    SELECT 1 FROM quickbooks_transactions qbt
    WHERE qbt.document_id = d.id
  )
  AND d.submitted_at < NOW() - INTERVAL '1 hour';
```

#### xenett_validations
Quality control validation from Xenett.

**Key Fields:**
- `validation_status`: passed, failed, warning
- `errors_found`: Array of Xenett errors
- `resolved`: Whether accountant has addressed the issue

**Usage:**
```sql
-- Unresolved Xenett errors
SELECT
  xv.validation_status,
  xv.errors_found,
  d.document_type,
  qbt.quickbooks_transaction_id
FROM xenett_validations xv
JOIN quickbooks_transactions qbt ON xv.quickbooks_transaction_id = qbt.id
JOIN documents d ON qbt.document_id = d.id
WHERE xv.resolved = false
  AND xv.validation_status = 'failed'
ORDER BY xv.validated_at DESC;
```

### 6. Configuration Tables

#### company_policies
Expense policies, approval chains, category restrictions.

**Key Fields:**
- `conditions`: JSON defining when policy applies
- `actions`: JSON defining what should happen
- `priority`: Higher priority policies evaluated first

**Example Policy:**
```json
{
  "conditions": {
    "category": "alcohol",
    "amount_cents": {">": 0}
  },
  "actions": {
    "require_approval": "manager",
    "add_warning": "Alcohol expenses require manager approval per company policy"
  }
}
```

**Usage:**
```sql
-- Get applicable policies for a transaction
SELECT policy_name, actions
FROM company_policies
WHERE company_id = 'uuid'
  AND is_active = true
  AND (
    -- Evaluate conditions (simplified, actual would use jsonb operators)
    conditions->>'category' = 'alcohol'
  )
ORDER BY priority DESC;
```

#### category_mappings
Company-specific categorization rules (learned and manual).

**Key Fields:**
- `vendor_pattern`: Regex for matching vendor names
- `description_keywords`: Keywords that suggest this category
- `times_accepted` / `times_overridden`: Track accuracy

**Usage:**
```sql
-- Find category mapping for a vendor
SELECT category, subcategory, gl_account_id
FROM category_mappings
WHERE company_id = 'uuid'
  AND vendor_pattern ~* 'staples'
  AND is_active = true
ORDER BY confidence DESC
LIMIT 1;

-- Mapping accuracy
SELECT
  category,
  times_accepted,
  times_overridden,
  (times_accepted::FLOAT / NULLIF(times_accepted + times_overridden, 0)) as accuracy
FROM category_mappings
WHERE company_id = 'uuid'
  AND times_matched > 10
ORDER BY accuracy DESC;
```

### 7. Audit & Compliance Tables

#### audit_log
**IMMUTABLE** - Complete audit trail for compliance.

**Partitioned by month** with 7-year retention for compliance.

**Key Fields:**
- `event_type`: What happened (INSERT_transactions, UPDATE_approvals, etc.)
- `actor_type`: Who did it (user, claude_agent, system)
- `changes`: Before/after JSON for updates

**Usage:**
```sql
-- Full audit trail for a document
SELECT
  event_type,
  actor_type,
  actor_id,
  changes,
  occurred_at
FROM audit_log
WHERE entity_type = 'document'
  AND entity_id = 'document_uuid'
ORDER BY occurred_at;

-- Who posted QB transactions today
SELECT
  actor_id,
  COUNT(*) as transactions_posted
FROM audit_log
WHERE event_type = 'INSERT_quickbooks_transactions'
  AND occurred_at::DATE = CURRENT_DATE
GROUP BY actor_id;

-- Track changes to a specific transaction
SELECT
  event_type,
  actor_id,
  changes->'old'->>'category' as old_category,
  changes->'new'->>'category' as new_category,
  occurred_at
FROM audit_log
WHERE entity_type = 'transactions'
  AND entity_id = 'transaction_uuid'
  AND event_type = 'UPDATE_transactions'
ORDER BY occurred_at;
```

## Key Views

### v_document_audit_trail
Complete processing history for a document from upload → QB posting.

**Usage:**
```sql
SELECT * FROM v_document_audit_trail
WHERE document_id = 'uuid'
ORDER BY processing_at;
```

**Returns:**
- Document metadata
- All processing events with confidence scores
- Questions asked and answers
- Approvals granted/denied
- QuickBooks posting details
- Xenett validation results

### v_accountant_review_queue
Dashboard view for accountants to see what needs review.

**Usage:**
```sql
-- High priority items (low confidence or needs approval)
SELECT * FROM v_accountant_review_queue
WHERE avg_confidence < 0.75
  OR needs_approval = true
ORDER BY submitted_at DESC;
```

### v_vendor_intelligence
Vendor spending patterns and categorization accuracy.

**Usage:**
```sql
-- Top vendors by spend
SELECT * FROM v_vendor_intelligence
WHERE company_id = 'uuid'
ORDER BY total_spent DESC
LIMIT 20;

-- Vendors with low categorization confidence
SELECT * FROM v_vendor_intelligence
WHERE avg_categorization_confidence < 0.80
  AND total_transactions > 5;
```

### v_daily_metrics
Daily performance metrics for monitoring.

**Usage:**
```sql
-- Last 30 days performance
SELECT
  date,
  documents_received,
  same_day_posting_rate,
  avg_confidence
FROM v_daily_metrics
WHERE company_id = 'uuid'
  AND date > CURRENT_DATE - INTERVAL '30 days'
ORDER BY date DESC;
```

## Key Functions

### get_or_create_vendor()
Fuzzy-match vendor or create new.

**Usage:**
```sql
-- Will find "Amazon" even if you pass "AMZN"
SELECT get_or_create_vendor(
  'company_uuid',
  'AMZN',
  0.85 -- similarity threshold
);
```

### calculate_processing_metrics()
Calculate performance metrics for a time period.

**Usage:**
```sql
SELECT * FROM calculate_processing_metrics(
  'company_uuid',
  '2025-10-01'::TIMESTAMP,
  '2025-10-31'::TIMESTAMP
);
```

**Returns:**
- total_documents
- avg_confidence
- straight_through_rate (% without human intervention)
- avg_questions (per document)
- avg_processing_time_ms

## Common Query Patterns

### 1. Daily Operations

**Get today's submitted documents:**
```sql
SELECT
  d.id,
  d.document_type,
  u.full_name as submitted_by,
  d.status,
  t.amount_cents::FLOAT / 100 as amount
FROM documents d
LEFT JOIN users u ON d.submitted_by = u.id
LEFT JOIN transactions t ON d.id = t.document_id
WHERE d.company_id = 'uuid'
  AND d.submitted_at::DATE = CURRENT_DATE
ORDER BY d.submitted_at DESC;
```

**Documents stuck in processing:**
```sql
SELECT
  d.id,
  d.status,
  d.submitted_at,
  NOW() - d.submitted_at as time_in_processing
FROM documents d
WHERE d.status = 'processing'
  AND d.submitted_at < NOW() - INTERVAL '15 minutes'
ORDER BY d.submitted_at;
```

### 2. Performance Monitoring

**Agent performance:**
```sql
SELECT
  agent_name,
  stage,
  AVG(confidence_score) as avg_confidence,
  AVG(processing_time_ms) as avg_time_ms,
  COUNT(*) as executions
FROM processing_events
WHERE company_id = 'uuid'
  AND created_at > NOW() - INTERVAL '7 days'
GROUP BY agent_name, stage
ORDER BY executions DESC;
```

**Slow queries:**
```sql
SELECT
  agent_name,
  document_id,
  processing_time_ms,
  created_at
FROM processing_events
WHERE processing_time_ms > 5000 -- 5 seconds
ORDER BY processing_time_ms DESC
LIMIT 20;
```

### 3. Financial Reports

**Monthly spending by category:**
```sql
SELECT
  category,
  COUNT(*) as transaction_count,
  SUM(amount_cents)::FLOAT / 100 as total_spent,
  AVG(amount_cents)::FLOAT / 100 as avg_amount
FROM transactions t
JOIN documents d ON t.document_id = d.id
WHERE t.company_id = 'uuid'
  AND t.transaction_date >= DATE_TRUNC('month', CURRENT_DATE)
  AND d.status = 'posted'
GROUP BY category
ORDER BY total_spent DESC;
```

**Spending by department:**
```sql
SELECT
  t.department,
  COUNT(*) as transactions,
  SUM(t.amount_cents)::FLOAT / 100 as total_spent
FROM transactions t
JOIN documents d ON t.document_id = d.id
WHERE t.company_id = 'uuid'
  AND t.transaction_date BETWEEN '2025-10-01' AND '2025-10-31'
  AND d.status = 'posted'
GROUP BY t.department
ORDER BY total_spent DESC;
```

### 4. Audit Queries

**All actions by a user:**
```sql
SELECT
  event_type,
  entity_type,
  occurred_at,
  changes
FROM audit_log
WHERE actor_type = 'user'
  AND actor_id = 'user_uuid'
  AND occurred_at > NOW() - INTERVAL '30 days'
ORDER BY occurred_at DESC;
```

**Track a transaction's full lifecycle:**
```sql
WITH transaction_docs AS (
  SELECT document_id FROM transactions WHERE id = 'trans_uuid'
)
SELECT
  al.occurred_at,
  al.event_type,
  al.actor_type,
  al.actor_id,
  al.changes
FROM audit_log al
WHERE al.entity_type IN ('document', 'transaction', 'approval', 'quickbooks_transactions')
  AND (
    al.entity_id = 'trans_uuid'
    OR al.entity_id IN (SELECT document_id FROM transaction_docs)
  )
ORDER BY al.occurred_at;
```

## Performance Considerations

### Partitioning Strategy

**Monthly Partitions (Auto-created):**
- `documents`: 2-year retention
- `processing_events`: 1-year retention
- `audit_log`: 7-year retention (compliance)

**Partition Maintenance:**
```sql
-- Create next month's partition (run weekly via cron)
CREATE TABLE documents_y2025m11 PARTITION OF documents
  FOR VALUES FROM ('2025-11-01') TO ('2025-12-01');

CREATE TABLE processing_events_y2025m11 PARTITION OF processing_events
  FOR VALUES FROM ('2025-11-01') TO ('2025-12-01');

CREATE TABLE audit_log_y2025m11 PARTITION OF audit_log
  FOR VALUES FROM ('2025-11-01') TO ('2025-12-01');

-- Archive old partitions
ALTER TABLE documents DETACH PARTITION documents_y2023m10;
-- Move to cold storage, then DROP
```

### Index Maintenance

**Regular Maintenance (monthly):**
```sql
-- Update statistics for query planner
ANALYZE documents;
ANALYZE transactions;
ANALYZE processing_events;

-- Reclaim space
VACUUM ANALYZE documents;
VACUUM ANALYZE transactions;

-- Reindex if needed (can be done CONCURRENTLY)
REINDEX INDEX CONCURRENTLY idx_documents_company_status;
```

### Query Optimization

**Use prepared statements for common queries:**
```sql
PREPARE get_pending_docs (UUID) AS
  SELECT * FROM documents
  WHERE company_id = $1 AND status = 'needs_review';

EXECUTE get_pending_docs('company_uuid');
```

**Monitor slow queries:**
```sql
-- Enable pg_stat_statements extension
CREATE EXTENSION pg_stat_statements;

-- Find slow queries
SELECT
  query,
  calls,
  mean_exec_time,
  total_exec_time
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;
```

## Security Considerations

### Row-Level Security (RLS)

Enable RLS for multi-tenant isolation:

```sql
ALTER TABLE documents ENABLE ROW LEVEL SECURITY;

CREATE POLICY company_isolation ON documents
  FOR ALL
  TO application_user
  USING (company_id = current_setting('app.company_id')::UUID);

-- In application, set the company context:
SET app.company_id = 'company_uuid';
```

### Encryption

**Sensitive data encryption:**
```sql
-- Use pgcrypto for sensitive fields
CREATE EXTENSION pgcrypto;

-- Example: Encrypt QuickBooks tokens
UPDATE quickbooks_sync_state
SET access_token_encrypted = pgp_sym_encrypt(
  'token_value',
  current_setting('app.encryption_key')
);

-- Decrypt
SELECT pgp_sym_decrypt(
  access_token_encrypted::bytea,
  current_setting('app.encryption_key')
) FROM quickbooks_sync_state;
```

### Audit Actor Context

Set actor context before operations:

```sql
-- Application sets these before making changes
SET app.actor_type = 'user';
SET app.actor_id = 'user@example.com';

-- Triggers automatically log with this context
INSERT INTO transactions (...) VALUES (...);
-- audit_log entry created with actor_type='user', actor_id='user@example.com'
```

## Migration Strategy

### Initial Setup

1. **Create extensions:**
```bash
psql -d bookkeeping -c "CREATE EXTENSION IF NOT EXISTS uuid-ossp;"
psql -d bookkeeping -c "CREATE EXTENSION IF NOT EXISTS pg_trgm;"
psql -d bookkeeping -c "CREATE EXTENSION IF NOT EXISTS btree_gin;"
```

2. **Run schema:**
```bash
psql -d bookkeeping -f database-schema.sql
```

3. **Create initial partitions:**
```bash
./scripts/create-partitions.sh --months 3
```

4. **Import QuickBooks data:**
```bash
node scripts/sync-from-quickbooks.js --initial-sync
```

### Ongoing Migrations

Use migration tool (e.g., Flyway, Liquibase):

```sql
-- V002__add_project_tracking.sql
ALTER TABLE transactions ADD COLUMN project_id UUID REFERENCES projects(id);
CREATE INDEX idx_transactions_project ON transactions(project_id);
```

## Backup & Recovery

### Backup Strategy

```bash
# Daily full backup
pg_dump bookkeeping -Fc > backup-$(date +%Y%m%d).dump

# Continuous WAL archiving for point-in-time recovery
# In postgresql.conf:
# wal_level = replica
# archive_mode = on
# archive_command = 'cp %p /backup/wal/%f'

# Backup audit_log separately with longer retention
pg_dump bookkeeping -t audit_log -Fc > audit-$(date +%Y%m%d).dump
```

### Recovery

```bash
# Restore from backup
pg_restore -d bookkeeping backup-20251028.dump

# Point-in-time recovery
pg_restore -d bookkeeping backup-20251028.dump
# Restore WAL files and set recovery target:
# recovery_target_time = '2025-10-28 12:00:00'
```

## Monitoring Queries

### System Health

```sql
-- Database size
SELECT pg_size_pretty(pg_database_size('bookkeeping'));

-- Table sizes
SELECT
  schemaname,
  tablename,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- Active connections
SELECT count(*) FROM pg_stat_activity;

-- Long-running queries
SELECT
  pid,
  now() - query_start AS duration,
  query
FROM pg_stat_activity
WHERE state = 'active'
  AND now() - query_start > interval '5 minutes'
ORDER BY duration DESC;
```

### Application Health

```sql
-- Documents pending too long
SELECT
  COUNT(*) FILTER (WHERE status = 'pending') as pending,
  COUNT(*) FILTER (WHERE status = 'processing') as processing,
  COUNT(*) FILTER (WHERE status = 'needs_review') as needs_review
FROM documents
WHERE submitted_at > NOW() - INTERVAL '24 hours';

-- QuickBooks sync health
SELECT
  company_id,
  last_successful_api_call,
  consecutive_failures,
  is_healthy
FROM quickbooks_sync_state
WHERE is_healthy = false OR consecutive_failures > 0;
```

## Troubleshooting

### Common Issues

**Issue: Document stuck in processing**
```sql
-- Find stuck documents
SELECT id, status, submitted_at
FROM documents
WHERE status = 'processing'
  AND submitted_at < NOW() - INTERVAL '30 minutes';

-- Check for errors in processing_events
SELECT agent_name, errors
FROM processing_events
WHERE document_id = 'stuck_doc_uuid'
  AND errors IS NOT NULL;

-- Manual reset (use with caution)
UPDATE documents
SET status = 'pending', updated_at = NOW()
WHERE id = 'stuck_doc_uuid';
```

**Issue: Low confidence scores**
```sql
-- Find patterns in low confidence
SELECT
  pe.agent_name,
  t.category,
  v.name as vendor,
  AVG(pe.confidence_score) as avg_conf
FROM processing_events pe
JOIN transactions t ON pe.transaction_id = t.id
LEFT JOIN vendors v ON t.vendor_id = v.id
WHERE pe.confidence_score < 0.70
GROUP BY pe.agent_name, t.category, v.name
HAVING COUNT(*) > 5
ORDER BY avg_conf;

-- Add category mappings to improve
INSERT INTO category_mappings (company_id, vendor_pattern, category, gl_account_id, confidence)
VALUES ('uuid', 'vendor_pattern', 'Office Supplies', 'gl_uuid', 0.90);
```

**Issue: QuickBooks posting failures**
```sql
-- Find failed posting attempts
SELECT
  d.id,
  d.document_type,
  pe.errors
FROM documents d
JOIN processing_events pe ON d.id = pe.document_id
WHERE d.status = 'approved'
  AND pe.agent_name = 'quickbooks-poster'
  AND pe.errors IS NOT NULL
ORDER BY pe.created_at DESC;

-- Check QB sync state
SELECT * FROM quickbooks_sync_state WHERE is_healthy = false;
```

## Next Steps

1. **Deploy Schema**: Run `database-schema.sql` on PostgreSQL instance
2. **Create Partitions**: Set up automated partition creation
3. **Import QuickBooks Data**: Sync initial COA and vendors
4. **Configure Backups**: Set up automated backup schedule
5. **Enable Monitoring**: Configure alerting on key metrics
6. **Load Test**: Simulate document volume to tune indexes
