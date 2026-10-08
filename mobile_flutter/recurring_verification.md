# Recurring payments verification

Verified on 8 October 2026. A debug APK was built after approval and copied to `C:\Dev\Expense App\homebudget-v2-debug.apk`. The copy was checked against the build output using SHA-256.

- Flutter analyze: no issues.
- Flutter tests: 48 passed, including contextual help and draft-preservation checks.
- Firestore emulator rules tests: 26 passed; matching rules deployed to home-budget-app-c038d.
- Tutorial: all 14 slides checked at 360×800, 320×640, 280×520 and 240×480 with 1.4× text scaling, without Flutter layout exceptions. Previews are illustrative Flutter layouts, not captured screenshots from a physical phone.
- Recurring grouping and summaries tested with 100, 1,000 and 10,000 records, including records outside the selected obligation month. No hidden 500-record cap remains in recurring status.

Contextual help for all nine screen/form topics was also checked on a 240×480 screen with 1.4× text scaling. Tests verify that closing help and switching to the full tour retain an expense draft, and that help returns to the unchanged budget dialog.

## Physical-device acceptance still required

1. Create Rent at 1,000 EUR, Home, shared. Enter an ordinary Home/Rent/EUR/shared expense of 400 EUR. Confirm its suggestion: paid 400, remaining 600.
2. Record 600 EUR for the same obligation month: paid 1,000, remaining zero. Try 700 EUR instead and verify the overpayment confirmation.
3. Unlink the second payment: spending is unchanged and recurring remaining becomes 600. Delete the first payment: spending falls and remaining becomes 1,000.
4. Edit an unlinked ordinary expense and link it through Recurring payment; verify no second expense appears.
5. Create a template in Dining, record two author-owned payments, then correct it to Home using the current-month scope. Verify Home, category totals and budget alerts reflect actual updated expenses. Test future-only scope separately.
6. Have another household member contribute a payment. Verify current-month bulk correction is disabled, while each author can unlink and correct their own expense.
7. Test cached viewing and queued payment writes, reconnection, and simultaneous payments on two phones. Creating a first monthly snapshot and legacy migration require a connection. Concurrent balance confirmations reflect the balance known at the time; eventual overpayments and mismatching payment fields are shown for review.

These automated timings validate local algorithms, not Android rendering, Firebase latency or production two-device behavior. Legacy records did not store historical expected amounts; upgrade reconstructs the expectation from the available template and keeps the original expense. Production expense data was not edited by the test suite.
