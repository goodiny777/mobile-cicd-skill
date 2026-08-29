# Driving App Store Connect with Claude in Chrome

Use this only when the user asks you to configure the console for them and the `mcp__claude-in-chrome__*` tools are available (load them with one ToolSearch call: `tabs_context_mcp, navigate, read_page, find, computer, form_input, get_page_text, tabs_create_mcp`). The user must already be signed in to App Store Connect in that Chrome; you never handle their Apple ID or 2FA.

## Hard limits

1. **Never type a secret value.** When you reach an Environment Variable row whose value is a secret, fill the *name*, tick *Keep value redacted*, and stop: tell the user which field to fill, wait for them to say it's done, then re-read the page and continue. Same for the Play service-account JSON.
2. **Never delete.** No deleting workflows, start conditions you didn't add, environment variables, tester groups, or secrets. Disabling is fine. Deleting the default *Branch Changes → main* condition is the one exception, and only after the tag condition exists and you've read the page to confirm both.
3. **Read before you act.** `get_page_text` or `read_page` each screen. ASC labels drift ("Manage Workflows" / "Workflows", "Custom Tags" / "Tags beginning with"); match on meaning, not memorised text.
4. **One workflow only.** Confirm the workflow name in the page header before every edit; ASC lists all workflows in a sidebar and it's easy to land on the wrong one.
5. **Stop on doubt.** If a screen doesn't look like what the console reference describes, stop and ask — don't explore.

## Sequence

Follow `xcode-cloud-console.md` §B in order. For each row:

1. Navigate / click into the section.
2. Read the page; confirm the current value.
3. If it already matches — record "already set" and move on (say so to the user; this is common after Xcode's onboarding).
4. If not — change it, read the page again to verify, then record the value for runbook §10.

Recommended order because of dependencies: name → Clean off → Environment Variables (names + redaction; values by the user) → Start Conditions (add tag condition, verify, then remove branch condition) → Archive action / Distribution Preparation → Post-actions → Save.

ASC saves per-section; look for the Save button state after each change and read the page to confirm it persisted.

## Verification screen

After saving, navigate to the workflow overview and read it once more. Compare against the target table and produce the §10 AS-CONFIGURED table from what the page shows — not from what you intended. Point out any row that differs.

## When Chrome isn't available

Do the same walk verbally: quote the row from `xcode-cloud-console.md`, ask the user to set it, and ask them to paste back what the page says (never a value). Fill §10 from their answers.
