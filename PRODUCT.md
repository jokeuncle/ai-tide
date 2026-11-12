# AI 潮汐

## Platform
Native macOS 14+, local SwiftUI desktop application.

## Purpose
Visualize actual observed network bytes belonging to cryptographically identified AI client processes. User-approved direction: exquisite jade/copper tide spheres, precise traffic charts, a compact menu-bar view. No guessed project attribution, thinking status, tokens, costs, or request counts.

## Implementation decisions
Swift / SwiftUI, a local Swift package and bundled .app. The initial collector uses the operating system's nettop tool; this machine has no Developer ID signing identity for a Network Extension. No proxy, certificate interception, root privilege, or network setting changes. No prompts, credentials, clipboard, browser history, or message contents are collected.

## Accuracy contract
Only trust a valid Apple-anchored vendor signature plus a specific allowed signing identifier. Label Codex separately from ChatGPT even when its application directory is ChatGPT.app. Record PID plus process birth time and executable path; recheck around sampling. First observations, counter resets, collection errors and missing samples never produce invented rates. Rates describe observed TCP/UDP process bytes, including background traffic and proxy legs, not model usage. Short-lived flows and processes can be missed; observed totals are not a billing or complete traffic ledger.

## Delivery and validation
Build a runnable app, meaningful parser/identity/counter tests, a bounded local transfer verification, and actual installed AI process measurements. Make failures and unavailable data visible. Save sanitized evidence under evidence/. Release is local only; quit app / delete dist/ reverses it. No account or system configuration changes.
