-- ============================================================================
-- COMPREHENSIVE DATABASE SCHEMA FOR INTELLIGENT BOOKKEEPING SYSTEM
-- ============================================================================
-- PostgreSQL 15+
-- Handles: Dext integration, Claude processing, QuickBooks sync, Audit trail
--
-- Design Principles:
-- 1. Immutability: Never delete, only mark as archived/superseded
-- 2. Full audit trail: Every change logged with reasoning
-- 3. Idempotency: Safe to replay events
-- 4. Performance: Indexed for common query patterns
-- 5. Scalability: Partitioned for growth
-- ============================================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm"; -- For fuzzy text search
CREATE EXTENSION IF NOT EXISTS "btree_gin"; -- For composite indexes

-- ============================================================================
-- CORE DOMAIN TABLES
-- ============================================================================

-- Companies/Clients (for accounting firm managing multiple businesses)
CREATE TABLE companies (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  quickbooks_realm_id TEXT UNIQUE NOT NULL,
  dext_organization_id TEXT,
  xenett_client_id TEXT,

  -- Settings
  settings JSONB DEFAULT '{}', -- Company-specific rules, limits, GL mappings
  timezone TEXT DEFAULT 'America/New_York',
  fiscal_year_end TEXT DEFAULT '12-31', -- MM-DD format

  -- Status
  status TEXT DEFAULT 'active', -- active, suspended, archived
  onboarded_at TIMESTAMP DEFAULT NOW(),
  archived_at TIMESTAMP,

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_companies_status ON companies(status) WHERE status = 'active';
CREATE INDEX idx_companies_qb_realm ON companies(quickbooks_realm_id);

-- Users (employees, managers, accountants)
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id UUID NOT NULL REFERENCES companies(id),

  -- Identity
  email TEXT NOT NULL,
  full_name TEXT NOT NULL,
  employee_id TEXT, -- Company's internal ID

  -- Role & Permissions
  role TEXT NOT NULL, -- employee, manager, director, vp, accountant, admin
  department TEXT,
  cost_center TEXT,

  -- Expense limits (in cents)
  single_transaction_limit INTEGER DEFAULT 50000, -- $500.00
  monthly_limit INTEGER,

  -- Contact preferences
  notification_preferences JSONB DEFAULT '{"slack": true, "email": true}',
  slack_user_id TEXT,
  phone TEXT,

  -- Status
  status TEXT DEFAULT 'active', -- active, inactive, archived
  hired_at DATE,
  terminated_at DATE,

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),

  UNIQUE(company_id, email)
);

CREATE INDEX idx_users_company ON users(company_id) WHERE status = 'active';
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_slack ON users(slack_user_id) WHERE slack_user_id IS NOT NULL;
CREATE INDEX idx_users_role ON users(company_id, role);

-- Vendors (enriched beyond QuickBooks data)
CREATE TABLE vendors (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id UUID NOT NULL REFERENCES companies(id),

  -- Core data
  name TEXT NOT NULL,
  name_normalized TEXT NOT NULL, -- Lowercase, no punctuation for matching
  quickbooks_vendor_id TEXT,
  dext_supplier_id TEXT,

  -- Contact
  website TEXT,
  email TEXT,
  phone TEXT,
  address JSONB,

  -- Intelligence (learned over time)
  typical_categories TEXT[], -- Most common expense categories
  average_transaction_amount INTEGER, -- In cents
  typical_gl_codes TEXT[],
  payment_terms TEXT, -- Net 30, etc.

  -- Metadata
  vendor_type TEXT, -- supplier, contractor, utility, etc.
  tax_id TEXT,
  is_1099_vendor BOOLEAN DEFAULT FALSE,

  -- Claude learning
  processing_notes JSONB DEFAULT '[]', -- Historical notes from Claude agents
  confidence_stats JSONB DEFAULT '{}', -- Track categorization accuracy

  -- Status
  status TEXT DEFAULT 'active',
  first_transaction_at TIMESTAMP,
  last_transaction_at TIMESTAMP,

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),

  UNIQUE(company_id, quickbooks_vendor_id)
);

CREATE INDEX idx_vendors_company ON vendors(company_id) WHERE status = 'active';
CREATE INDEX idx_vendors_qb_id ON vendors(quickbooks_vendor_id);
CREATE INDEX idx_vendors_name_trgm ON vendors USING gin(name_normalized gin_trgm_ops);
CREATE INDEX idx_vendors_categories ON vendors USING gin(typical_categories);

-- Chart of Accounts (cached from QuickBooks)
CREATE TABLE chart_of_accounts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id UUID NOT NULL REFERENCES companies(id),

  -- QuickBooks data
  quickbooks_account_id TEXT NOT NULL,
  account_number TEXT,
  account_name TEXT NOT NULL,
  account_type TEXT NOT NULL, -- Expense, Asset, Liability, etc.
  account_subtype TEXT,
  parent_account_id UUID REFERENCES chart_of_accounts(id),

  -- Metadata
  description TEXT,
  is_active BOOLEAN DEFAULT TRUE,
  is_tax_account BOOLEAN DEFAULT FALSE,

  -- Claude hints
  keywords TEXT[], -- Keywords that suggest this account
  typical_vendors UUID[], -- Vendor IDs typically using this account

  -- Sync tracking
  last_synced_from_qb TIMESTAMP,

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),

  UNIQUE(company_id, quickbooks_account_id)
);

CREATE INDEX idx_coa_company ON chart_of_accounts(company_id) WHERE is_active = TRUE;
CREATE INDEX idx_coa_type ON chart_of_accounts(company_id, account_type);
CREATE INDEX idx_coa_keywords ON chart_of_accounts USING gin(keywords);

-- ============================================================================
-- DOCUMENT & TRANSACTION TABLES
-- ============================================================================

-- Documents (from Dext)
CREATE TABLE documents (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id UUID NOT NULL REFERENCES companies(id),

  -- Source tracking
  source TEXT NOT NULL, -- dext, manual_upload, email, mobile_app
  source_id TEXT, -- Dext document ID
  source_metadata JSONB DEFAULT '{}',

  -- Document details
  document_type TEXT NOT NULL, -- receipt, invoice, bill, statement
  document_date DATE,

  -- File storage
  original_filename TEXT,
  storage_url TEXT NOT NULL, -- S3/blob URL
  file_size_bytes INTEGER,
  mime_type TEXT,
  ocr_text TEXT, -- Full extracted text for searching

  -- Submitter
  submitted_by UUID REFERENCES users(id),
  submitted_at TIMESTAMP DEFAULT NOW(),
  submission_context JSONB DEFAULT '{}', -- How/where it was submitted

  -- Status tracking
  status TEXT DEFAULT 'pending', -- pending, processing, needs_review, approved, posted, rejected, archived

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- Partition by month for scalability
CREATE TABLE documents_y2025m10 PARTITION OF documents
  FOR VALUES FROM ('2025-10-01') TO ('2025-11-01');

CREATE INDEX idx_documents_company_status ON documents(company_id, status);
CREATE INDEX idx_documents_source ON documents(source, source_id);
CREATE INDEX idx_documents_submitted_by ON documents(submitted_by);
CREATE INDEX idx_documents_date ON documents(document_date);
CREATE INDEX idx_documents_ocr_text ON documents USING gin(to_tsvector('english', ocr_text));

-- Extracted Transactions (from Dext, enhanced by Claude)
CREATE TABLE transactions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id UUID NOT NULL REFERENCES companies(id),
  document_id UUID NOT NULL REFERENCES documents(id),

  -- Basic transaction data
  transaction_date DATE NOT NULL,
  vendor_id UUID REFERENCES vendors(id),
  vendor_name_raw TEXT, -- As extracted from document

  -- Amounts (stored in cents to avoid float issues)
  amount_cents INTEGER NOT NULL,
  currency TEXT DEFAULT 'USD',
  tax_amount_cents INTEGER,
  tip_amount_cents INTEGER,

  -- Categorization
  category TEXT, -- High-level category (Office Supplies, Travel, etc.)
  subcategory TEXT,
  gl_account_id UUID REFERENCES chart_of_accounts(id),

  -- Business context
  description TEXT,
  business_purpose TEXT, -- Why this expense was incurred
  project_code TEXT,
  department TEXT,
  cost_center TEXT,

  -- Flags
  is_billable BOOLEAN DEFAULT FALSE,
  is_personal BOOLEAN DEFAULT FALSE,
  is_reimbursable BOOLEAN DEFAULT FALSE,

  -- Split handling
  is_split BOOLEAN DEFAULT FALSE,
  parent_transaction_id UUID REFERENCES transactions(id), -- If this is part of a split
  split_percentage DECIMAL(5,2), -- If split, what % of original

  -- Line items (for detailed receipts)
  line_items JSONB DEFAULT '[]',

  -- Status
  status TEXT DEFAULT 'extracted', -- extracted, enhanced, validated, posted

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_transactions_company ON transactions(company_id);
CREATE INDEX idx_transactions_document ON transactions(document_id);
CREATE INDEX idx_transactions_date ON transactions(company_id, transaction_date DESC);
CREATE INDEX idx_transactions_vendor ON transactions(vendor_id);
CREATE INDEX idx_transactions_gl_account ON transactions(gl_account_id);
CREATE INDEX idx_transactions_status ON transactions(status);
CREATE INDEX idx_transactions_split ON transactions(parent_transaction_id) WHERE is_split = TRUE;

-- ============================================================================
-- CLAUDE PROCESSING TABLES
-- ============================================================================

-- Processing Pipeline Events
CREATE TABLE processing_events (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id UUID NOT NULL REFERENCES companies(id),
  document_id UUID NOT NULL REFERENCES documents(id),
  transaction_id UUID REFERENCES transactions(id),

  -- Agent information
  agent_name TEXT NOT NULL, -- context-analyzer, policy-enforcer, etc.
  agent_model TEXT, -- claude-sonnet-4, claude-opus-4
  stage TEXT NOT NULL, -- extraction, context_analysis, policy_check, etc.

  -- Processing data
  input_data JSONB NOT NULL,
  output_data JSONB NOT NULL,

  -- Decision tracking
  decision TEXT, -- approve, reject, needs_review, needs_clarification
  reasoning TEXT, -- Claude's explanation of the decision
  confidence_score DECIMAL(3,2), -- 0.00 to 1.00

  -- Performance
  processing_time_ms INTEGER,
  tokens_used INTEGER,

  -- Results
  errors JSONB DEFAULT '[]',
  warnings JSONB DEFAULT '[]',

  created_at TIMESTAMP DEFAULT NOW()
);

-- Partition by month
CREATE TABLE processing_events_y2025m10 PARTITION OF processing_events
  FOR VALUES FROM ('2025-10-01') TO ('2025-11-01');

CREATE INDEX idx_processing_company ON processing_events(company_id);
CREATE INDEX idx_processing_document ON processing_events(document_id);
CREATE INDEX idx_processing_agent ON processing_events(agent_name, stage);
CREATE INDEX idx_processing_confidence ON processing_events(confidence_score);
CREATE INDEX idx_processing_created ON processing_events(created_at DESC);

-- Claude Learning Database (for improving over time)
CREATE TABLE claude_learnings (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id UUID NOT NULL REFERENCES companies(id),

  -- What was learned
  learning_type TEXT NOT NULL, -- vendor_category, gl_mapping, policy_pattern
  context JSONB NOT NULL, -- What triggered this learning

  -- The learning
  pattern TEXT, -- Description of the pattern
  rule JSONB, -- Structured rule that can be applied

  -- Validation
  initial_confidence DECIMAL(3,2),
  times_applied INTEGER DEFAULT 0,
  times_correct INTEGER DEFAULT 0,
  times_corrected INTEGER DEFAULT 0,
  current_confidence DECIMAL(3,2),

  -- Source
  learned_from_document_id UUID REFERENCES documents(id),
  learned_from_correction BOOLEAN DEFAULT FALSE,

  -- Status
  status TEXT DEFAULT 'active', -- active, superseded, invalidated

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_learnings_company ON claude_learnings(company_id, learning_type) WHERE status = 'active';
CREATE INDEX idx_learnings_confidence ON claude_learnings(current_confidence DESC);

-- ============================================================================
-- HUMAN INTERACTION TABLES
-- ============================================================================

-- User Queries (when Claude needs clarification)
CREATE TABLE user_queries (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id UUID NOT NULL REFERENCES companies(id),
  document_id UUID NOT NULL REFERENCES documents(id),
  transaction_id UUID REFERENCES transactions(id),

  -- Question details
  question_type TEXT NOT NULL, -- category_unclear, split_needed, business_purpose, etc.
  question_text TEXT NOT NULL,
  context JSONB, -- Additional context for the question

  -- Questioning agent
  asked_by_agent TEXT NOT NULL,
  asked_to_user_id UUID REFERENCES users(id),

  -- Delivery
  delivery_method TEXT, -- slack, email, dashboard
  delivery_metadata JSONB, -- Message IDs, thread IDs, etc.

  -- Response
  response_text TEXT,
  response_structured JSONB, -- Parsed/structured response
  responded_at TIMESTAMP,
  response_time_seconds INTEGER,

  -- Follow-up
  clarification_sufficient BOOLEAN,
  required_followup BOOLEAN DEFAULT FALSE,

  asked_at TIMESTAMP DEFAULT NOW(),
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_queries_company ON user_queries(company_id);
CREATE INDEX idx_queries_document ON user_queries(document_id);
CREATE INDEX idx_queries_user ON user_queries(asked_to_user_id);
CREATE INDEX idx_queries_unanswered ON user_queries(asked_at) WHERE responded_at IS NULL;

-- Approvals (policy exceptions, high-value transactions)
CREATE TABLE approvals (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id UUID NOT NULL REFERENCES companies(id),
  document_id UUID NOT NULL REFERENCES documents(id),
  transaction_id UUID NOT NULL REFERENCES transactions(id),

  -- Approval type
  approval_type TEXT NOT NULL, -- amount_threshold, policy_exception, new_vendor, etc.
  approval_reason TEXT NOT NULL,

  -- Routing
  required_approver_role TEXT, -- manager, director, accountant
  assigned_to_user_id UUID REFERENCES users(id),
  escalated_from_user_id UUID REFERENCES users(id), -- If escalated

  -- Request details
  requested_by_agent TEXT,
  request_context JSONB,
  requested_at TIMESTAMP DEFAULT NOW(),

  -- Decision
  decision TEXT, -- approved, rejected, modified, escalated
  decision_notes TEXT,
  modifications JSONB, -- If approved with changes
  decided_by_user_id UUID REFERENCES users(id),
  decided_at TIMESTAMP,

  -- Delivery
  notification_sent_via TEXT,
  notification_metadata JSONB,

  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_approvals_company ON approvals(company_id);
CREATE INDEX idx_approvals_document ON approvals(document_id);
CREATE INDEX idx_approvals_assigned ON approvals(assigned_to_user_id) WHERE decided_at IS NULL;
CREATE INDEX idx_approvals_pending ON approvals(requested_at) WHERE decision IS NULL;

-- ============================================================================
-- QUICKBOOKS INTEGRATION TABLES
-- ============================================================================

-- QuickBooks Sync State
CREATE TABLE quickbooks_sync_state (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id UUID NOT NULL REFERENCES companies(id),

  -- OAuth
  access_token_encrypted TEXT NOT NULL,
  refresh_token_encrypted TEXT NOT NULL,
  token_expires_at TIMESTAMP NOT NULL,

  -- Sync status
  last_full_sync_at TIMESTAMP,
  last_incremental_sync_at TIMESTAMP,
  sync_cursor TEXT, -- For incremental syncing

  -- Health
  last_successful_api_call TIMESTAMP,
  consecutive_failures INTEGER DEFAULT 0,
  is_healthy BOOLEAN DEFAULT TRUE,

  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE UNIQUE INDEX idx_qb_sync_company ON quickbooks_sync_state(company_id);

-- QuickBooks Transactions (posted to QB)
CREATE TABLE quickbooks_transactions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id UUID NOT NULL REFERENCES companies(id),
  document_id UUID NOT NULL REFERENCES documents(id),
  transaction_id UUID NOT NULL REFERENCES transactions(id),

  -- QuickBooks IDs
  quickbooks_transaction_id TEXT NOT NULL,
  quickbooks_transaction_type TEXT NOT NULL, -- Expense, Bill, Purchase, etc.
  quickbooks_sync_token TEXT, -- For updates

  -- Posting details
  posted_by_user_id UUID REFERENCES users(id),
  posted_at TIMESTAMP DEFAULT NOW(),

  -- Request/Response
  qb_request_payload JSONB NOT NULL,
  qb_response_payload JSONB NOT NULL,

  -- Attachment
  receipt_attached BOOLEAN DEFAULT FALSE,
  attachment_id TEXT,

  -- Reversal tracking
  is_reversed BOOLEAN DEFAULT FALSE,
  reversed_at TIMESTAMP,
  reversed_by_user_id UUID REFERENCES users(id),
  reversal_reason TEXT,
  reversal_transaction_id UUID REFERENCES quickbooks_transactions(id),

  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_qb_trans_company ON quickbooks_transactions(company_id);
CREATE INDEX idx_qb_trans_document ON quickbooks_transactions(document_id);
CREATE INDEX idx_qb_trans_qb_id ON quickbooks_transactions(quickbooks_transaction_id);
CREATE INDEX idx_qb_trans_posted ON quickbooks_transactions(posted_at DESC);
CREATE UNIQUE INDEX idx_qb_trans_unique ON quickbooks_transactions(company_id, quickbooks_transaction_id);

-- Xenett Validation Results
CREATE TABLE xenett_validations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id UUID NOT NULL REFERENCES companies(id),
  quickbooks_transaction_id UUID NOT NULL REFERENCES quickbooks_transactions(id),

  -- Validation results
  validation_status TEXT NOT NULL, -- passed, failed, warning
  errors_found JSONB DEFAULT '[]',
  warnings_found JSONB DEFAULT '[]',

  -- Xenett metadata
  xenett_check_id TEXT,
  checks_run TEXT[],

  -- Resolution
  resolved BOOLEAN DEFAULT FALSE,
  resolved_at TIMESTAMP,
  resolved_by_user_id UUID REFERENCES users(id),
  resolution_notes TEXT,

  validated_at TIMESTAMP DEFAULT NOW(),
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_xenett_company ON xenett_validations(company_id);
CREATE INDEX idx_xenett_qb_trans ON xenett_validations(quickbooks_transaction_id);
CREATE INDEX idx_xenett_unresolved ON xenett_validations(validated_at) WHERE resolved = FALSE;

-- ============================================================================
-- CONFIGURATION & POLICY TABLES
-- ============================================================================

-- Company Policies (expense rules, approval chains)
CREATE TABLE company_policies (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id UUID NOT NULL REFERENCES companies(id),

  -- Policy details
  policy_type TEXT NOT NULL, -- expense_limit, approval_required, category_restriction
  policy_name TEXT NOT NULL,
  description TEXT,

  -- Rule definition
  conditions JSONB NOT NULL, -- When does this policy apply?
  actions JSONB NOT NULL, -- What should happen?

  -- Examples:
  -- conditions: {"amount_cents": {">": 50000}, "category": "equipment"}
  -- actions: {"require_approval": "manager", "flag_for_review": true}

  -- Priority (higher = evaluated first)
  priority INTEGER DEFAULT 100,

  -- Status
  is_active BOOLEAN DEFAULT TRUE,
  effective_from DATE,
  effective_until DATE,

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_policies_company ON company_policies(company_id, priority DESC) WHERE is_active = TRUE;
CREATE INDEX idx_policies_type ON company_policies(policy_type);

-- Category Mappings (company-specific categorization rules)
CREATE TABLE category_mappings (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id UUID NOT NULL REFERENCES companies(id),

  -- Pattern matching
  vendor_pattern TEXT, -- Regex or fuzzy match
  description_keywords TEXT[],
  amount_range JSONB, -- {"min": 0, "max": 50000}

  -- Target mapping
  category TEXT NOT NULL,
  subcategory TEXT,
  gl_account_id UUID REFERENCES chart_of_accounts(id),

  -- Confidence
  confidence DECIMAL(3,2) DEFAULT 0.80,

  -- Learning
  times_matched INTEGER DEFAULT 0,
  times_accepted INTEGER DEFAULT 0,
  times_overridden INTEGER DEFAULT 0,

  -- Status
  is_active BOOLEAN DEFAULT TRUE,
  created_by TEXT, -- claude_agent or user_email

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_category_mappings_company ON category_mappings(company_id) WHERE is_active = TRUE;
CREATE INDEX idx_category_mappings_vendor ON category_mappings USING gin(vendor_pattern gin_trgm_ops);

-- ============================================================================
-- AUDIT & COMPLIANCE TABLES
-- ============================================================================

-- Complete Audit Log (immutable)
CREATE TABLE audit_log (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id UUID NOT NULL REFERENCES companies(id),

  -- What happened
  event_type TEXT NOT NULL, -- document_uploaded, transaction_posted, approval_granted, etc.
  entity_type TEXT NOT NULL, -- document, transaction, approval, etc.
  entity_id UUID NOT NULL,

  -- Who did it
  actor_type TEXT NOT NULL, -- user, claude_agent, system
  actor_id TEXT NOT NULL, -- user.id, agent name, or 'system'

  -- Changes
  changes JSONB, -- Before/after for updates
  metadata JSONB, -- Additional context

  -- Timestamp (immutable)
  occurred_at TIMESTAMP DEFAULT NOW()
);

-- Partition by month for compliance retention
CREATE TABLE audit_log_y2025m10 PARTITION OF audit_log
  FOR VALUES FROM ('2025-10-01') TO ('2025-11-01');

CREATE INDEX idx_audit_company ON audit_log(company_id, occurred_at DESC);
CREATE INDEX idx_audit_entity ON audit_log(entity_type, entity_id);
CREATE INDEX idx_audit_actor ON audit_log(actor_type, actor_id);
CREATE INDEX idx_audit_event_type ON audit_log(event_type);

-- Data Retention Tracking
CREATE TABLE data_retention (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id UUID NOT NULL REFERENCES companies(id),

  -- Retention policy
  entity_type TEXT NOT NULL,
  retention_period_days INTEGER NOT NULL,

  -- Execution
  last_cleanup_at TIMESTAMP,
  next_cleanup_at TIMESTAMP,

  -- Stats
  total_records_archived INTEGER DEFAULT 0,
  total_records_deleted INTEGER DEFAULT 0,

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE UNIQUE INDEX idx_retention_company_entity ON data_retention(company_id, entity_type);

-- ============================================================================
-- PERFORMANCE & ANALYTICS TABLES
-- ============================================================================

-- Processing Statistics (for monitoring & optimization)
CREATE TABLE processing_stats (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id UUID NOT NULL REFERENCES companies(id),

  -- Time period
  period_start TIMESTAMP NOT NULL,
  period_end TIMESTAMP NOT NULL,
  granularity TEXT NOT NULL, -- hourly, daily, weekly

  -- Volume metrics
  documents_processed INTEGER DEFAULT 0,
  transactions_created INTEGER DEFAULT 0,

  -- Performance metrics
  avg_processing_time_ms INTEGER,
  p95_processing_time_ms INTEGER,
  p99_processing_time_ms INTEGER,

  -- Accuracy metrics
  avg_confidence_score DECIMAL(3,2),
  straight_through_rate DECIMAL(3,2), -- % requiring no human intervention

  -- Human interaction metrics
  questions_asked INTEGER DEFAULT 0,
  avg_response_time_seconds INTEGER,
  approvals_required INTEGER DEFAULT 0,

  -- Error metrics
  processing_errors INTEGER DEFAULT 0,
  qb_posting_errors INTEGER DEFAULT 0,

  -- Cost metrics
  total_tokens_used BIGINT DEFAULT 0,
  estimated_cost_usd DECIMAL(10,4),

  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_stats_company_period ON processing_stats(company_id, period_start DESC);
CREATE INDEX idx_stats_granularity ON processing_stats(granularity, period_start DESC);

-- ============================================================================
-- VIEWS FOR COMMON QUERIES
-- ============================================================================

-- Complete audit trail for a document
CREATE VIEW v_document_audit_trail AS
SELECT
  d.id AS document_id,
  d.company_id,
  d.source,
  d.document_type,
  d.document_date,
  d.status AS current_status,
  u.full_name AS submitted_by,
  d.submitted_at,

  -- Processing events
  pe.agent_name,
  pe.stage,
  pe.decision,
  pe.reasoning,
  pe.confidence_score,
  pe.created_at AS processing_at,

  -- User queries
  uq.question_text,
  uq.response_text,
  uq.responded_at,

  -- Approvals
  a.approval_type,
  a.decision AS approval_decision,
  a.decided_at AS approval_decided_at,
  approver.full_name AS approved_by,

  -- QuickBooks posting
  qbt.quickbooks_transaction_id,
  qbt.posted_at AS qb_posted_at,
  poster.full_name AS qb_posted_by,

  -- Xenett validation
  xv.validation_status,
  xv.errors_found AS xenett_errors

FROM documents d
LEFT JOIN users u ON d.submitted_by = u.id
LEFT JOIN processing_events pe ON d.id = pe.document_id
LEFT JOIN user_queries uq ON d.id = uq.document_id
LEFT JOIN approvals a ON d.id = a.document_id
LEFT JOIN users approver ON a.decided_by_user_id = approver.id
LEFT JOIN quickbooks_transactions qbt ON d.id = qbt.document_id
LEFT JOIN users poster ON qbt.posted_by_user_id = poster.id
LEFT JOIN xenett_validations xv ON qbt.id = xv.quickbooks_transaction_id

ORDER BY d.submitted_at DESC, pe.created_at, uq.asked_at, a.requested_at;

-- Pending items for accountant review
CREATE VIEW v_accountant_review_queue AS
SELECT
  d.id AS document_id,
  c.name AS company_name,
  d.document_type,
  d.document_date,
  d.submitted_at,
  u.full_name AS submitted_by,

  t.vendor_name_raw AS vendor,
  t.amount_cents::FLOAT / 100 AS amount,
  t.category,
  t.description,

  -- Processing summary
  (
    SELECT AVG(confidence_score)
    FROM processing_events
    WHERE document_id = d.id
  ) AS avg_confidence,

  (
    SELECT COUNT(*)
    FROM user_queries
    WHERE document_id = d.id AND responded_at IS NOT NULL
  ) AS questions_answered,

  (
    SELECT COUNT(*)
    FROM approvals
    WHERE document_id = d.id AND decision = 'approved'
  ) AS approvals_granted,

  -- Flags
  EXISTS(
    SELECT 1 FROM approvals
    WHERE document_id = d.id AND decision IS NULL
  ) AS needs_approval,

  d.storage_url

FROM documents d
JOIN companies c ON d.company_id = c.id
LEFT JOIN users u ON d.submitted_by = u.id
LEFT JOIN transactions t ON d.id = t.document_id

WHERE d.status IN ('needs_review', 'approved')
  AND NOT EXISTS (
    SELECT 1 FROM quickbooks_transactions
    WHERE document_id = d.id
  )

ORDER BY d.document_date DESC;

-- Vendor intelligence summary
CREATE VIEW v_vendor_intelligence AS
SELECT
  v.id,
  v.company_id,
  v.name,
  v.quickbooks_vendor_id,

  -- Transaction statistics
  COUNT(t.id) AS total_transactions,
  SUM(t.amount_cents)::FLOAT / 100 AS total_spent,
  AVG(t.amount_cents)::FLOAT / 100 AS avg_transaction,
  MIN(t.transaction_date) AS first_transaction,
  MAX(t.transaction_date) AS last_transaction,

  -- Most common category
  MODE() WITHIN GROUP (ORDER BY t.category) AS most_common_category,

  -- Most common GL account
  MODE() WITHIN GROUP (ORDER BY coa.account_name) AS most_common_gl_account,

  -- Confidence metrics
  AVG(
    SELECT confidence_score
    FROM processing_events pe
    WHERE pe.transaction_id = t.id
      AND pe.agent_name = 'context-analyzer'
  ) AS avg_categorization_confidence

FROM vendors v
LEFT JOIN transactions t ON v.id = t.vendor_id
LEFT JOIN chart_of_accounts coa ON t.gl_account_id = coa.id

GROUP BY v.id, v.company_id, v.name, v.quickbooks_vendor_id;

-- Daily processing metrics
CREATE VIEW v_daily_metrics AS
SELECT
  company_id,
  DATE(submitted_at) AS date,

  COUNT(*) AS documents_received,
  COUNT(*) FILTER (WHERE status = 'posted') AS documents_posted,
  COUNT(*) FILTER (WHERE status = 'needs_review') AS documents_pending,

  AVG(
    SELECT AVG(confidence_score)
    FROM processing_events pe
    WHERE pe.document_id = d.id
  ) AS avg_confidence,

  COUNT(
    SELECT 1
    FROM quickbooks_transactions qbt
    WHERE qbt.document_id = d.id
      AND DATE(qbt.posted_at) = DATE(d.submitted_at)
  )::FLOAT / NULLIF(COUNT(*), 0) AS same_day_posting_rate,

  AVG(
    SELECT COUNT(*)
    FROM user_queries uq
    WHERE uq.document_id = d.id
  ) AS avg_questions_per_document

FROM documents d
GROUP BY company_id, DATE(submitted_at)
ORDER BY date DESC;

-- ============================================================================
-- TRIGGERS FOR AUTOMATION
-- ============================================================================

-- Auto-update timestamps
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER companies_updated_at BEFORE UPDATE ON companies
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER users_updated_at BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER vendors_updated_at BEFORE UPDATE ON vendors
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER documents_updated_at BEFORE UPDATE ON documents
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER transactions_updated_at BEFORE UPDATE ON transactions
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Audit logging trigger
CREATE OR REPLACE FUNCTION log_audit_event()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO audit_log (
    company_id,
    event_type,
    entity_type,
    entity_id,
    actor_type,
    actor_id,
    changes,
    metadata
  ) VALUES (
    COALESCE(NEW.company_id, OLD.company_id),
    TG_OP || '_' || TG_TABLE_NAME,
    TG_TABLE_NAME,
    COALESCE(NEW.id, OLD.id),
    COALESCE(current_setting('app.actor_type', true), 'system'),
    COALESCE(current_setting('app.actor_id', true), 'unknown'),
    jsonb_build_object('old', to_jsonb(OLD), 'new', to_jsonb(NEW)),
    '{}'::jsonb
  );
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Apply audit logging to critical tables
CREATE TRIGGER audit_quickbooks_transactions
  AFTER INSERT OR UPDATE OR DELETE ON quickbooks_transactions
  FOR EACH ROW EXECUTE FUNCTION log_audit_event();

CREATE TRIGGER audit_approvals
  AFTER INSERT OR UPDATE ON approvals
  FOR EACH ROW EXECUTE FUNCTION log_audit_event();

-- Vendor statistics update trigger
CREATE OR REPLACE FUNCTION update_vendor_stats()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE vendors
  SET
    last_transaction_at = NEW.transaction_date,
    first_transaction_at = COALESCE(first_transaction_at, NEW.transaction_date),
    average_transaction_amount = (
      SELECT AVG(amount_cents)::INTEGER
      FROM transactions
      WHERE vendor_id = NEW.vendor_id
    )
  WHERE id = NEW.vendor_id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER transaction_update_vendor
  AFTER INSERT ON transactions
  FOR EACH ROW EXECUTE FUNCTION update_vendor_stats();

-- ============================================================================
-- FUNCTIONS FOR COMMON OPERATIONS
-- ============================================================================

-- Get or create vendor (with fuzzy matching)
CREATE OR REPLACE FUNCTION get_or_create_vendor(
  p_company_id UUID,
  p_vendor_name TEXT,
  p_similarity_threshold FLOAT DEFAULT 0.85
)
RETURNS UUID AS $$
DECLARE
  v_vendor_id UUID;
  v_normalized_name TEXT;
BEGIN
  -- Normalize the name
  v_normalized_name := LOWER(REGEXP_REPLACE(p_vendor_name, '[^a-z0-9]', '', 'g'));

  -- Try exact match first
  SELECT id INTO v_vendor_id
  FROM vendors
  WHERE company_id = p_company_id
    AND name_normalized = v_normalized_name
  LIMIT 1;

  IF v_vendor_id IS NOT NULL THEN
    RETURN v_vendor_id;
  END IF;

  -- Try fuzzy match
  SELECT id INTO v_vendor_id
  FROM vendors
  WHERE company_id = p_company_id
    AND similarity(name_normalized, v_normalized_name) > p_similarity_threshold
  ORDER BY similarity(name_normalized, v_normalized_name) DESC
  LIMIT 1;

  IF v_vendor_id IS NOT NULL THEN
    RETURN v_vendor_id;
  END IF;

  -- Create new vendor
  INSERT INTO vendors (company_id, name, name_normalized)
  VALUES (p_company_id, p_vendor_name, v_normalized_name)
  RETURNING id INTO v_vendor_id;

  RETURN v_vendor_id;
END;
$$ LANGUAGE plpgsql;

-- Calculate processing metrics for a time period
CREATE OR REPLACE FUNCTION calculate_processing_metrics(
  p_company_id UUID,
  p_start_time TIMESTAMP,
  p_end_time TIMESTAMP
)
RETURNS TABLE (
  total_documents INTEGER,
  avg_confidence DECIMAL(3,2),
  straight_through_rate DECIMAL(3,2),
  avg_questions INTEGER,
  avg_processing_time_ms INTEGER
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    COUNT(DISTINCT d.id)::INTEGER,
    AVG(pe.confidence_score)::DECIMAL(3,2),
    (COUNT(DISTINCT d.id) FILTER (
      WHERE NOT EXISTS (
        SELECT 1 FROM user_queries uq WHERE uq.document_id = d.id
      ) AND NOT EXISTS (
        SELECT 1 FROM approvals a WHERE a.document_id = d.id
      )
    )::FLOAT / NULLIF(COUNT(DISTINCT d.id), 0))::DECIMAL(3,2),
    AVG((
      SELECT COUNT(*)
      FROM user_queries uq
      WHERE uq.document_id = d.id
    ))::INTEGER,
    AVG(pe.processing_time_ms)::INTEGER

  FROM documents d
  LEFT JOIN processing_events pe ON d.id = pe.document_id

  WHERE d.company_id = p_company_id
    AND d.submitted_at BETWEEN p_start_time AND p_end_time;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- INDEXES FOR REPORTING & ANALYTICS
-- ============================================================================

-- Reporting indexes
CREATE INDEX idx_reporting_posted_by_month ON quickbooks_transactions(
  company_id,
  DATE_TRUNC('month', posted_at)
);

CREATE INDEX idx_reporting_transactions_by_category ON transactions(
  company_id,
  category,
  transaction_date
) WHERE status = 'posted';

CREATE INDEX idx_reporting_vendor_spending ON transactions(
  company_id,
  vendor_id,
  transaction_date DESC
);

-- Performance monitoring indexes
CREATE INDEX idx_perf_slow_processing ON processing_events(
  processing_time_ms DESC,
  created_at DESC
) WHERE processing_time_ms > 5000; -- Flag slow operations > 5 seconds

CREATE INDEX idx_perf_low_confidence ON processing_events(
  confidence_score,
  created_at DESC
) WHERE confidence_score < 0.70; -- Flag low confidence decisions

-- ============================================================================
-- COMMENTS FOR DOCUMENTATION
-- ============================================================================

COMMENT ON TABLE documents IS 'Source documents from Dext or direct upload';
COMMENT ON TABLE transactions IS 'Extracted and enhanced transaction data';
COMMENT ON TABLE processing_events IS 'Complete log of all Claude agent processing';
COMMENT ON TABLE claude_learnings IS 'Machine learning improvements over time';
COMMENT ON TABLE user_queries IS 'Questions asked to users for clarification';
COMMENT ON TABLE approvals IS 'Approval workflow tracking';
COMMENT ON TABLE quickbooks_transactions IS 'Successfully posted QB transactions';
COMMENT ON TABLE xenett_validations IS 'Quality control validation results';
COMMENT ON TABLE audit_log IS 'Immutable audit trail for compliance';

COMMENT ON COLUMN transactions.amount_cents IS 'Amount in cents to avoid floating point issues';
COMMENT ON COLUMN processing_events.confidence_score IS 'Agent confidence 0.00-1.00';
COMMENT ON COLUMN vendors.name_normalized IS 'Lowercase, alphanumeric only for fuzzy matching';
COMMENT ON COLUMN claude_learnings.current_confidence IS 'Updated as pattern is validated';

-- ============================================================================
-- INITIAL SEED DATA (Example)
-- ============================================================================

-- Example: Common expense categories
-- INSERT INTO ... (would be in a separate seed file)

-- ============================================================================
-- MIGRATION NOTES
-- ============================================================================

/*
Migration Strategy:

1. Create all base tables first (companies, users, vendors, chart_of_accounts)
2. Sync initial data from QuickBooks (vendors, COA)
3. Create partitioned tables (documents, processing_events, audit_log)
4. Create views and functions
5. Set up triggers
6. Create indexes (can be done CONCURRENTLY to avoid locks)

Partitioning Strategy:
- documents: Monthly partitions, 2-year retention
- processing_events: Monthly partitions, 1-year retention
- audit_log: Monthly partitions, 7-year retention (compliance)

Auto-create next month's partition:
  - Cron job runs weekly
  - Creates partition for next 2 months if not exists

Performance Tuning:
- Regularly ANALYZE tables for query planning
- VACUUM partitioned tables monthly
- Monitor slow queries with pg_stat_statements
- Archive old partitions to cold storage

Backup Strategy:
- Continuous WAL archiving
- Daily full backups
- 90-day backup retention
- Audit log: separate backup with 7-year retention
*/
