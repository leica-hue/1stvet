# Firebase Payment Storage Troubleshooting Guide

## Project Info
- **Firebase Project**: `fureverhealthy-admin`
- **Collection Name**: `payment` (singular, not "payments")

## Step-by-Step Testing

### 1. Test Payment Submission
When you click "Submit for Verification", you should see these messages IN ORDER:

1. ✅ **"Uploading proof..."**
2. ✅ **"Screenshot uploaded: [url]..."** ← Confirms upload worked
3. ✅ **"Saving to collection: payment (vetId: xyz)"** ← Shows what's being saved
4. ✅ **"✅ Payment doc created! ID: [document-id]"** ← **THIS MEANS IT WORKED!**
5. ✅ **"✅ Payment submitted & Premium activated..."** ← Final success

### 2. If You See Error Messages

#### "Upload failed. Check console for details"
- Screenshot upload to Firebase Storage failed
- Press F12 → Console tab → look for red errors
- Check Firebase Storage rules (see below)

#### "Firebase error: permission-denied"
- Your Firestore Security Rules are blocking writes
- **FIX**: Update Firestore Rules (see section below)

#### "Firebase error: [other error]"
- Copy the exact error and check Firebase Console
- May indicate project misconfiguration

### 3. Fix Firestore Security Rules

If you see "permission-denied", update your Firestore Rules:

**Go to:** https://console.firebase.google.com/project/fureverhealthy-admin/firestore/rules

**Replace the rules with:**

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Allow authenticated vets to create payment records
    match /payment/{paymentId} {
      allow create: if request.auth != null;
      allow read: if request.auth != null;
      allow update: if request.auth != null;
    }
    
    // Allow vets to read/write their own profile
    match /vets/{vetId} {
      allow read, write: if request.auth != null && request.auth.uid == vetId;
    }
    
    // Other collections (add as needed)
    match /{document=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```

Click **"Publish"** to save the rules.

### 4. Fix Firebase Storage Rules

If screenshot upload fails, update Storage Rules:

**Go to:** https://console.firebase.google.com/project/fureverhealthy-admin/storage/rules

**Replace with:**

```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /payment_proofs/{allPaths=**} {
      allow read: if request.auth != null;
      allow write: if request.auth != null;
    }
    match /{allPaths=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```

Click **"Publish"** to save.

### 5. Verify Data in Firebase Console

**Go to:** https://console.firebase.google.com/project/fureverhealthy-admin/firestore/data

Look for:
- Collection: **`payment`** (singular)
- Documents: Each submission creates a new document with auto-generated ID
- Fields in each document:
  - `vetId`: Your vet user ID
  - `transactionId`: The GCash reference number you entered
  - `screenshotUrl`: URL to the uploaded image
  - `amount`: 499.0
  - `status`: "Pending"
  - `submissionTime`: Timestamp
  - `premiumUntilCalculated`: Timestamp

### 6. Check Browser Console for Errors

1. Open your app in Chrome
2. Press **F12** to open DevTools
3. Go to **Console** tab
4. Submit a payment
5. Look for RED error messages
6. Copy any errors you see

## Common Issues

### Issue: "It says success but I don't see data"
- Check you're in the **correct Firebase project** (fureverhealthy-admin)
- Look for collection **`payment`** not "payments"
- Refresh the Firestore page in Firebase Console

### Issue: "Screenshot upload fails"
- Check Firebase Storage rules (see section 4 above)
- Make sure Storage bucket exists: `fureverhealthy-admin.firebasestorage.app`

### Issue: "Nothing happens when I click submit"
- Check browser console (F12) for JavaScript errors
- Make sure you're logged in as a vet
- Ensure you filled in the GCash reference number
- Ensure you uploaded a screenshot

## Need More Help?

If none of this works, provide:
1. The exact error messages you see
2. Screenshot of browser console (F12)
3. Screenshot of your Firestore Rules

