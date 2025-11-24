# Firebase Storage Rules for ID Verification

## Quick Fix

Go to: **https://console.firebase.google.com/project/fureverhealthy-admin/storage/rules**

Replace your entire rules with this:

```javascript
rules_version = '2';

service firebase.storage {
  match /b/{bucket}/o {
    // VET ID VERIFICATIONS - Required for ID submission feature
    match /vet_id_verifications/{userId}/{filename} {
      allow write: if request.auth != null && request.auth.uid == userId;
      allow read: if request.auth != null;
    }
    
    // VET PROFILE IMAGES
    match /vet_profile_images/{userId}/{filename} {
      allow write: if request.auth != null && request.auth.uid == userId;
      allow read: if request.auth != null;
    }
    
    // PAYMENT SCREENSHOTS
    match /payment_proofs/{vetId}/{fileName} {
      allow write: if request.auth != null && request.auth.uid == vetId;
      allow read: if request.auth != null;
    }
    
    // PET IMAGES
    match /pet_images/{userId}/{fileName} {
      allow write: if request.auth != null && request.auth.uid == userId;
      allow read: if request.auth != null;
    }
    
    // USER PROFILE IMAGES
    match /profile_images/{userId}/{fileName} {
      allow write: if request.auth != null && request.auth.uid == userId;
      allow read: if request.auth != null;
    }
  }
}
```

## Steps to Apply

1. **Copy the rules above**
2. **Go to Firebase Console**: https://console.firebase.google.com/project/fureverhealthy-admin/storage/rules
3. **Paste the rules** into the editor
4. **Click "Publish"** (very important - rules won't take effect until published!)
5. **Wait 1-2 minutes** for rules to propagate
6. **Try uploading ID again**

## Verification

After publishing, you should see:
- ✅ Green checkmark next to "Published"
- ✅ No syntax errors in the rules editor
- ✅ The rule for `vet_id_verifications` is visible

## If Still Not Working

1. **Check you're logged in**: Make sure you're authenticated in the app
2. **Check user ID**: The `currentUserId` must match the `userId` in the path
3. **Try in incognito mode**: Sometimes browser cache can cause issues
4. **Check Firebase Console logs**: Look for any additional error messages

## Alternative: More Permissive Rule (for testing only)

If you need to test quickly, you can temporarily use this more permissive rule:

```javascript
rules_version = '2';

service firebase.storage {
  match /b/{bucket}/o {
    match /vet_id_verifications/{allPaths=**} {
      allow read, write: if request.auth != null;
    }
    // ... other rules
  }
}
```

**⚠️ Warning**: This allows any authenticated user to write to any vet's folder. Use only for testing, then switch back to the secure rules above.

