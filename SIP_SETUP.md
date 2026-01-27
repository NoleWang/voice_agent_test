# LiveKit Phone Number (Inbound) Setup Guide

This guide explains how to use **LiveKit Phone Numbers** for inbound calls only. The user calls the bank from their own phone number, then adds the LiveKit phone number as a second call and merges the calls. This keeps the bank seeing the user’s real (private) phone number, while LiveKit bridges the combined audio into the room.

## Overview

**Desired flow (no outbound dial from app):**

1. User calls the bank from the Phone app.
2. After the bank answers, user taps **Add Call**.
3. User dials the LiveKit phone number.
4. Merge calls. LiveKit receives the conference audio (user + bank) as a SIP participant in the room.

## Implementation Summary

### Backend

- No outbound SIP calls are initiated by the backend.
- The backend only provides LiveKit room tokens (via `/livekit/token`).

### iOS

- **LiveKitRoomView.swift**
  - Shows a call setup guide.
  - Provides **Call Bank** and **Call LiveKit Number** buttons (both use the native Phone app).
- **AppConfig.swift**
  - Reads `LIVEKIT_PHONE_NUMBER` from Info.plist.

## Required Setup Steps

### 1. Provision a LiveKit Phone Number

Follow LiveKit’s SIP/PSTN docs to register a phone number with your LiveKit project.

### 2. Update iOS Info.plist

Add your LiveKit phone number (E.164 format) to `Info.plist`:

```xml
<key>LIVEKIT_PHONE_NUMBER</key>
<string>+15551234567</string>
```

### 3. App Usage Flow

1. User completes the dispute form (selecting a bank).
2. User joins the LiveKit room.
3. In the room screen:
   - Tap **Call Bank** (or call from Phone app directly).
   - Tap **Add Call**, then **Call LiveKit Number**.
   - Merge the two calls so the agent hears the combined audio.

## Testing Checklist

- Verify the LiveKit phone number rings and is accepted.
- Confirm the LiveKit room receives a SIP participant when the number is called.
- Merge calls and verify the agent hears both the user and the bank agent.

## Additional Resources

- [LiveKit SIP Documentation](https://docs.livekit.io/telephony/start/sip-trunk-setup/)
