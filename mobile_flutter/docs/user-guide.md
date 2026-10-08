# Using HomeBudget

## Help wherever you are

Choose **Show me how to use this App** on the start screen for the complete tutorial. On a screen or supported form, select the **?** button in its header for relevant slides only. Use **Previous** and **Next** to move between slides, **Back to screen**, **Close**, or the phone’s Back button to return. **More help → Full tutorial** opens the complete guide. Help does not reset a draft, sign you out or change household data.

The visual examples use John Smith and Anna Smith, with invented amounts. They are illustrative previews rather than photographs of a user’s account.

## Account and household

Create an account, verify the email address and create a household, or enter a single-use invite code and wait for the owner’s approval. A saved session lets you open your connected household from the start screen without signing in again. Choose the main currency when creating the household.

## Home

The greeting, monthly remaining budget, spending pockets and recent activity summarize real expenses. If no total monthly budget is set, Home shows spending instead. **View all budgets and categories** opens Plan. **Add expense** opens the entry form. The avatar returns to the start screen without signing out.

## Expenses: Activity

Choose a month, **Last 30 days**, **All time**, or custom dates. Combine text search with category, currency and shared/personal filters. The list and displayed total cover the entries loaded for the selected period; use **Load more** to include additional entries. Each expense shows its original currency. Only its author can edit or delete it.

## Expenses: Plan

The owner can set the total monthly budget and tap each category to set its monthly limit. **Add category** creates a category. Its menu can rename or remove it; removal hides it from new-expense choices while preserving past expenses. Category allocations and the total monthly limit are separate: check the warning if allocations exceed the total.

## Recording an expense and other currencies

Enter an amount, category, currency, optional description, sharing choice and date. For a different currency, supply the rate as **1 expense currency = X main currency**. A 25 EUR purchase at 117.20 RSD contributes 2,930 RSD to household totals, while the individual expense remains 25 EUR.

## Expenses: Recurring

The owner sets an expected amount, original currency, category, sharing, due day and grace period. Creating the item creates an obligation, not actual spending. Record a payment or link an existing author-owned expense. The payment month identifies the obligation being paid and can differ from the expense’s date.

On saving an ordinary expense, matching category, currency, sharing and normalized description offers an explicit recurring link. A blank description can offer several matching candidates. Select the correct item or save it as an ordinary expense. **Link existing** connects a saved expense without creating a second expense.

A 1,000 EUR obligation paid with 400 EUR shows 600 EUR remaining; another 600 EUR completes it. Each confirmation compares the payment with the remaining amount. An excess payment requires confirmation and appears as overpaid. Insights warns only about an unpaid remainder after the due date and grace period.

Editing an amount recomputes the paid total. Unlinking removes its contribution to the obligation but keeps actual spending. Deleting removes the expense from spending and recurring paid totals. The monthly plan remains so the unpaid obligation is still visible.

### Correcting a recurring category

For a Dining → Home correction, **Only future payments** preserves this month’s saved category and prior expense records. **Also update this month’s linked payments** corrects the current records only if the owner authored all affected expenses and currency/sharing are unchanged. Earlier months and their expected amounts stay unchanged. With payments from another member, that author must unlink and correct their own expense. Concurrently added payments can require review; the recurring card flags mismatched fields.

## Insights

Select one or several categories for the six-month trend; clear the selection to show all. Current-month category warnings appear at 90% of the budget and above. Recurring overdue warnings show the remaining unpaid amount. Shared spending comparisons show the current month and totals since the owner’s reset. No automatic expense generation or background notifications are enabled.

## Settings and sharing

Choose light or dark appearance, a device PIN and biometric lock where supported. The device lock is separate from the Firebase account password. Share an invite through Copy or the phone’s standard share sheet; access requires owner approval. An owner can transfer ownership to an active member before leaving the household. Returning to the start screen keeps the session; **Sign out** ends it.

## Connectivity and monthly history

Firestore caches loaded data and queues writes when disconnected. Creating the first monthly recurring snapshot, upgrading a legacy link and confirmed deletion require connectivity. Shared totals across full history need an online aggregate query. Balances confirmed on two phones can change when another member’s payment arrives; the synchronized list shows the eventual paid and overpaid amounts.

Monthly expected amounts are stored separately from actual expenses. Older single-payment records did not contain historical expected amounts; their upgrade reconstructs that value from the available template while keeping the expense itself.
