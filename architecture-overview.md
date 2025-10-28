# Intelligent Bookkeeping System Architecture

## System Overview

This system leverages existing tools (Dext, Xenett, QuickBooks) with Claude as an intelligent orchestration layer that adds business context, handles exceptions, and manages human-in-the-loop workflows.

## Core Components

### 1. Existing Tools Integration

#### Dext (Document Capture & Extraction)
- **Role**: Receipt/invoice capture and OCR
- **Capabilities**: 99% accurate extraction, mobile app, email uploads
- **Output**: Structured transaction data
- **Integration**: Webhook events → Claude orchestrator

#### Xenett (Quality Control)
- **Role**: Transaction validation and error detection
- **Capabilities**: 100+ automated checks, book closing workflows
- **Integration**: Validates after QuickBooks posting

#### QuickBooks Online (Core Accounting)
- **Role**: General ledger and financial system of record
- **Integration**: API for creating transactions, querying data

### 2. Claude Orchestration Layer

#### Main Orchestrator
Central coordinator that:
- Listens for Dext webhook events
- Routes to specialized subagents
- Manages workflow state
- Coordinates human interactions
- Maintains audit trail

#### Specialized Subagents

**context-analyzer**
- Applies business-specific categorization rules
- Determines if expense is capital vs operational
- Assigns correct GL codes from company chart of accounts
- Evaluates against company policies

**policy-enforcer**
- Checks expense limits by category/employee
- Flags policy violations (e.g., alcohol, personal expenses)
- Determines approval requirements
- Routes to appropriate approver based on rules

**split-transaction-handler**
- Detects when expense should be split
- Handles multi-department allocations
- Manages project-based expense splitting
- Creates multiple QB entries with proper cross-references

**vendor-intelligence**
- Learns vendor patterns over time
- Suggests category based on historical data
- Flags new/unusual vendors for verification
- Maintains vendor metadata not in QuickBooks

**user-query-agent**
- Generates contextual clarifying questions
- Routes questions to submitter via Slack/email
- Parses natural language responses
- Updates transaction data based on answers

**approval-router**
- Implements approval workflows
- Escalates based on amount/category/policy
- Tracks approval chains
- Sends reminders for pending approvals

**reconciliation-agent**
- Matches Dext transactions to bank feeds
- Flags discrepancies (tips, fees, etc.)
- Suggests corrections
- Batch processes bank statement reconciliation

**audit-logger**
- Records all processing steps
- Captures agent decisions with reasoning
- Logs confidence scores
- Creates queryable audit trail

### 3. Data Flow

```
User submits receipt → Dext
  ↓
Dext extracts data → Webhook to Claude
  ↓
Claude context-analyzer: Adds business intelligence
  ↓
Claude policy-enforcer: Checks rules
  ↓
  ├─→ Low confidence / Complex case → Claude user-query-agent
  │     ↓
  │   Slack/Email question to submitter
  │     ↓
  │   Response captured → Context updated
  │     ↓
  ├─→ Policy violation → Claude approval-router
  │     ↓
  │   Routed to manager for approval
  │     ↓
  └─→ High confidence + Policy compliant
        ↓
      Staged for accountant review
        ↓
      Accountant approves in dashboard
        ↓
      Claude posts to QuickBooks via API
        ↓
      Xenett validates transaction
        ↓
      Complete - All logged to audit DB
```

### 4. Human-in-the-Loop Interfaces

#### For Submitters (Employees)
- **Slack bot**: Receives clarifying questions with buttons for quick answers
- **Email**: Longer form questions with reply-to parsing
- **Mobile notifications**: Urgent approvals needed

#### For Accountants
- **Web dashboard**: Review queue with risk scoring
- **Batch operations**: Approve multiple similar transactions
- **Exception viewer**: Focus on low-confidence items
- **Audit trail viewer**: Full transparency of Claude decisions

#### For Managers
- **Approval workflow**: Email/Slack approvals with one-click
- **Policy exception alerts**: Notified when rules are bent
- **Spending insights**: Claude-generated summaries

### 5. Audit Trail Database

**PostgreSQL Schema:**

```sql
-- Documents from Dext
CREATE TABLE dext_documents (
  id UUID PRIMARY KEY,
  dext_id TEXT UNIQUE,
  document_type TEXT, -- receipt, invoice, bill
  raw_data JSONB,
  received_at TIMESTAMP,
  status TEXT
);

-- Claude processing events
CREATE TABLE claude_processing (
  id UUID PRIMARY KEY,
  dext_document_id UUID REFERENCES dext_documents(id),
  agent_name TEXT,
  stage TEXT, -- context_analysis, policy_check, etc.
  input_data JSONB,
  output_data JSONB,
  reasoning TEXT, -- Claude's explanation
  confidence_score DECIMAL(3,2),
  processing_time_ms INTEGER,
  timestamp TIMESTAMP
);

-- User interactions
CREATE TABLE user_queries (
  id UUID PRIMARY KEY,
  dext_document_id UUID REFERENCES dext_documents(id),
  question TEXT,
  asked_via TEXT, -- slack, email
  asked_by TEXT, -- agent name
  asked_to TEXT, -- user email
  response TEXT,
  responded_at TIMESTAMP,
  response_parsed JSONB
);

-- Approval chains
CREATE TABLE approvals (
  id UUID PRIMARY KEY,
  dext_document_id UUID REFERENCES dext_documents(id),
  approval_type TEXT, -- policy_exception, amount_threshold
  required_approver TEXT,
  requested_at TIMESTAMP,
  decision TEXT, -- approved, rejected, modified
  notes TEXT,
  decided_at TIMESTAMP
);

-- QuickBooks postings
CREATE TABLE qb_postings (
  id UUID PRIMARY KEY,
  dext_document_id UUID REFERENCES dext_documents(id),
  qb_transaction_id TEXT,
  qb_type TEXT, -- expense, bill, etc.
  posted_by TEXT, -- email of accountant
  posted_at TIMESTAMP,
  qb_response JSONB,
  xenett_validation_status TEXT,
  xenett_errors JSONB
);

-- Audit views
CREATE VIEW audit_trail AS
SELECT
  d.dext_id,
  d.document_type,
  d.received_at,
  cp.agent_name,
  cp.stage,
  cp.confidence_score,
  uq.question,
  uq.response,
  a.approval_type,
  a.decision,
  qb.posted_at,
  qb.xenett_validation_status
FROM dext_documents d
LEFT JOIN claude_processing cp ON d.id = cp.dext_document_id
LEFT JOIN user_queries uq ON d.id = uq.dext_document_id
LEFT JOIN approvals a ON d.id = a.dext_document_id
LEFT JOIN qb_postings qb ON d.id = qb.dext_document_id
ORDER BY d.received_at DESC;
```

### 6. Configuration Files

#### Subagent Definitions

`.claude/agents/context-analyzer.md`:
```markdown
---
name: context-analyzer
model: claude-sonnet-4
tools: [Read, mcp__qb__get_chart_of_accounts, mcp__db__query_vendor_history]
max_iterations: 5
---

Analyze Dext-extracted transaction and add business context.

Input: Dext webhook data with extracted fields
Output: Enhanced transaction with:
- Refined category (more specific than Dext suggestion)
- Assigned GL code from company chart of accounts
- Capital vs operational expense determination
- Project/department allocation (if applicable)
- Confidence score with reasoning

Business Rules:
1. Office supplies under $500 → GL 5100
2. Equipment over $500 → GL 1500 (capital asset)
3. Meals over $50 → require business purpose note
4. Amazon purchases → check line items (often mixed supply/equipment)
5. Recurring vendors → apply learned patterns

Query vendor history to check:
- Historical category assignments
- Average transaction amounts
- Typical GL codes used
- Any notes from past transactions

Calculate confidence:
- Dext confidence * 0.3
- Vendor history match * 0.3
- Amount reasonableness * 0.2
- Category clarity * 0.2

If confidence < 0.80, generate clarifying question.
```

`.claude/agents/policy-enforcer.md`:
```markdown
---
name: policy-enforcer
model: claude-sonnet-4
tools: [Read, mcp__db__get_employee_limits]
max_iterations: 3
---

Enforce company expense policies.

Company Policies:
1. Expense limits by role:
   - Employee: $500 per transaction
   - Manager: $2,000 per transaction
   - Director: $5,000 per transaction
   - VP+: Unlimited

2. Prohibited without approval:
   - Alcohol (needs manager approval)
   - Personal items
   - Cash advances
   - Gift cards (needs director approval)

3. Receipt requirements:
   - All expenses require receipt
   - Meals over $25 require business purpose
   - Mileage requires destination/purpose

4. Split transaction rules:
   - Client meals: 50% deductible
   - Home office: Based on square footage %
   - Vehicle: Based on business use %

Check each transaction against policies.

Output:
- Policy compliance: compliant / needs_approval / violation
- Required approver (if applicable)
- Violation details
- Suggested correction (if violation)
```

`.claude/agents/split-transaction-handler.md`:
```markdown
---
name: split-transaction-handler
model: claude-sonnet-4
tools: [Read, mcp__qb__create_split_transaction]
max_iterations: 10
---

Handle transactions that need to be split across categories, departments, or projects.

Detect split scenarios:
1. Line items with different categories (e.g., Amazon: supplies + equipment)
2. Multi-department allocation (e.g., team outing: split by headcount)
3. Project-based work (e.g., consultant invoice: split by project hours)
4. Partial reimbursements (e.g., personal + business on same receipt)

For each split:
- Calculate allocation percentages
- Assign separate GL codes
- Create linked transactions in QB
- Maintain cross-reference in audit trail
- Flag if allocations don't sum to 100%

Ask for clarification if:
- Split not obvious from line items
- Project allocation percentages unknown
- Department split method unclear
```

`.claude/agents/user-query-agent.md`:
```markdown
---
name: user-query-agent
model: claude-sonnet-4
tools: [mcp__slack__send_message, mcp__email__send]
max_iterations: 5
---

Generate contextual questions for submitters when clarification needed.

Question generation principles:
1. Be specific with context
2. Provide multiple choice when possible
3. Include relevant details (amount, vendor, date)
4. Explain why asking
5. Make it quick to answer (buttons, emoji reactions)

Example questions:

**Low confidence on category:**
"I found your $1,245.67 receipt from Staples on Oct 28.

Dext extracted these items:
- Desk chair: $800
- Printer paper: $45.67
- USB drives: $400

Should this be categorized as:
🪑 Equipment (capital asset)
📄 Office Supplies (expense)
🔀 Split (chair=equipment, rest=supplies)

Context: Equipment over $500 goes to GL 1500 and affects depreciation."

**Unclear business purpose:**
"Your $87.50 dinner at Olive Garden on Oct 28 needs a business purpose note.

Was this:
👥 Client meal (enter client name)
🤝 Team meeting (enter attendees)
✈️ Business travel meal (enter destination)
❌ Personal (will not expense)"

**New vendor:**
"First time seeing 'XYZ Consulting LLC' - $2,500 invoice.

Can you confirm:
- What service did they provide?
- Which project/department?
- Is this a one-time or recurring vendor?
- Do we have a signed contract on file?"

Response handling:
- Parse natural language or button clicks
- Update transaction data
- Log interaction to audit trail
- Resume processing workflow
```

### 7. Custom MCP Servers

#### mcp-server-dext
```javascript
// Tools:
// - dext__get_document
// - dext__list_pending
// - dext__get_line_items
// - dext__update_category
```

#### mcp-server-quickbooks
```javascript
// Tools:
// - qb__get_chart_of_accounts
// - qb__create_expense
// - qb__create_bill
// - qb__create_split_transaction
// - qb__attach_receipt
// - qb__get_vendor
// - qb__create_vendor
```

#### mcp-server-notifications
```javascript
// Tools:
// - slack__send_message
// - slack__send_interactive_message
// - email__send
// - email__parse_reply
```

#### mcp-server-audit
```javascript
// Tools:
// - audit__log_event
// - audit__get_document_trail
// - audit__search_by_vendor
// - audit__get_confidence_stats
```

## Implementation Phases

### Phase 1: Foundation (2-3 weeks)
- Set up PostgreSQL audit database
- Create webhook listener for Dext
- Build basic MCP servers (QB, Slack, audit)
- Deploy context-analyzer agent
- Test with 10 sample receipts manually

### Phase 2: Intelligence Layer (3-4 weeks)
- Deploy policy-enforcer agent
- Deploy split-transaction-handler
- Deploy user-query-agent
- Build Slack interactive workflows
- Train on historical data (3-6 months of past transactions)

### Phase 3: Human Interfaces (2-3 weeks)
- Build accountant review dashboard
- Create approval workflow UI
- Develop audit trail viewer
- Mobile-friendly interfaces

### Phase 4: Production & Monitoring (2 weeks)
- Xenett integration validation
- Performance optimization
- Error handling & retry logic
- Alerting & monitoring dashboards

### Phase 5: Learning & Refinement (Ongoing)
- Collect confidence scores vs actual outcomes
- Tune categorization models
- Refine business rules
- Expand to more complex scenarios

## Success Metrics

- **Straight-through processing rate**: % of transactions that go Dext → QB without human intervention
- **Question efficiency**: Avg questions asked per transaction
- **Time to posting**: Dext upload → QB posting time
- **Accountant time saved**: Hours per month reviewing transactions
- **Error rate**: Xenett-detected errors post-Claude processing
- **Audit trail completeness**: % of decisions with full reasoning
- **User satisfaction**: Submitter response time to queries

## Risk Mitigation

1. **Financial accuracy**: All transactions stage before posting, accountant final approval
2. **Data security**: Encryption at rest/transit, audit all access
3. **System reliability**: Retry logic, manual fallback workflows
4. **Compliance**: Full audit trail, no deletion of records
5. **Cost control**: Token usage monitoring, caching, model selection
