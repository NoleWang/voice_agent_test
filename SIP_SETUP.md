# LiveKit SIP Integration with Twilio Setup Guide

This guide explains how to set up LiveKit SIP integration with Twilio to enable outbound calls from the iOS app to bank phone numbers.

## Overview

The implementation allows users in the LiveKit room to call the bank's phone number (selected in DisputeTransactionFormView) directly from within the iOS app. The call is routed through LiveKit's SIP trunk to Twilio, which connects to the actual phone number.

## Implementation Summary

### Backend Changes (Python)

1. **New API Endpoint**: `/livekit/sip/outbound` (POST)
   - Accepts: `room` (string), `phone_number` (string)
   - Creates a SIP participant in the LiveKit room
   - Initiates outbound call through configured SIP trunk
   - Returns: success status, participant identity, SIP call ID

2. **Location**: `agent/RoomIO.py`
   - Added `SIPOutboundCallRequest` model
   - Added `create_sip_outbound_call` async endpoint

### iOS Changes

1. **DisputeTransactionFormView.swift**
   - Updated `LiveKitJoinInfo` to include `bankPhoneNumber` and `roomName`
   - Passes bank phone number to `LiveKitRoomView` when creating room

2. **LiveKitRoomView.swift**
   - Added `bankPhoneNumber` and `roomName` parameters
   - Added "Call Bank" button (shown when bank phone number is available)
   - Added call status tracking (`isCallingBank`, `bankCallStatus`)
   - Implemented `callBank()` function to initiate SIP outbound call

3. **LiveKitTokenAPI.swift**
   - Added `SIPOutboundCallResponse` struct
   - Added `createSIPOutboundCall()` function to call backend API

## Required Setup Steps

### 1. Configure Twilio SIP Trunk

1. Log in to your Twilio Console
2. Navigate to **SIP Trunks** section
3. Create a new SIP Trunk (or use existing)
4. Note your Twilio SIP domain (e.g., `yourdomain.pstn.twilio.com`)
5. Configure authentication credentials (username and password)

### 2. Configure LiveKit Outbound SIP Trunk

You need to create an outbound trunk in LiveKit that connects to Twilio:

1. Create a JSON file `outbound-trunk.json`:
```json
{
  "trunk": {
    "name": "Twilio Outbound Trunk",
    "address": "<your_twilio_sip_domain>",
    "numbers": ["+19725122160"],
    "auth_username": "<your_twilio_sip_username>",
    "auth_password": "<your_twilio_sip_password>"
  }
}
```

2. Replace placeholders:
   - `<your_twilio_sip_domain>`: Your Twilio SIP domain (e.g., `yourdomain.pstn.twilio.com`)
   - `<your_twilio_sip_username>`: Your Twilio SIP username
   - `<your_twilio_sip_password>`: Your Twilio SIP password
   - `+19725122160`: Your Twilio phone number (already configured)

3. Create the outbound trunk using LiveKit CLI:
```bash
lk sip outbound create outbound-trunk.json
```

4. Note the trunk ID/name (defaults to "twilio" if not specified)

### 3. Configure Backend Environment Variables

Add to your `.env` file or environment:

```bash
# Existing LiveKit variables
LIVEKIT_URL=wss://your-project.livekit.cloud
LIVEKIT_API_KEY=your_api_key
LIVEKIT_API_SECRET=your_api_secret

# New: SIP trunk name (should match the name used when creating the trunk)
LIVEKIT_SIP_TRUNK=twilio  # or whatever name you used
```

### 4. Verify Twilio Account Setup

Since you're using a Twilio trial account:

1. **Verify Phone Numbers**: Twilio trial accounts require you to verify phone numbers before calling them. Add the bank phone numbers you want to call to your verified numbers list in Twilio Console.

2. **Upgrade Consideration**: For production use, consider upgrading to a paid Twilio account to remove verification requirements and other limitations.

## Usage Flow

1. User fills out dispute form in `DisputeTransactionFormView`
2. User selects a bank (which includes the bank's phone number)
3. User clicks "Save" button
4. LiveKit room is created and user joins
5. In `LiveKitRoomView`, if a bank phone number is available, a "Call Bank" button appears
6. User clicks "Call Bank" button
7. iOS app sends request to backend `/livekit/sip/outbound` endpoint
8. Backend creates SIP participant in LiveKit room
9. LiveKit initiates outbound call through Twilio SIP trunk
10. Call is bridged into the LiveKit room
11. User can now speak with the bank agent through the LiveKit room

## Testing

1. **Test Backend Endpoint**:
   ```bash
   curl -X POST http://127.0.0.1:8000/livekit/sip/outbound \
     -H "Content-Type: application/json" \
     -d '{"room": "your-room-name", "phone_number": "+1234567890"}'
   ```

2. **Test from iOS App**:
   - Fill out dispute form
   - Select a bank with a phone number
   - Click "Save" to join LiveKit room
   - Click "Call Bank" button
   - Verify call connects and audio works

## Troubleshooting

1. **Call fails to initiate**:
   - Check LiveKit logs for SIP trunk errors
   - Verify SIP trunk is correctly configured in LiveKit
   - Verify Twilio credentials are correct
   - Check that phone number is in E.164 format (+1234567890)

2. **Call connects but no audio**:
   - Check Twilio SIP trunk media settings
   - Verify LiveKit room audio tracks are published/subscribed
   - Check network connectivity

3. **"SIP trunk not found" error**:
   - Verify `LIVEKIT_SIP_TRUNK` environment variable matches trunk name
   - List trunks: `lk sip outbound list`
   - Verify trunk exists and is active

## Additional Resources

- [LiveKit SIP Documentation](https://docs.livekit.io/telephony/start/sip-trunk-setup/)
- [Twilio SIP Documentation](https://www.twilio.com/docs/voice/api/sip-making-calls)
- [LiveKit Python SDK](https://docs.livekit.io/server-sdk/python/)
