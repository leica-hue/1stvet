# Firebase Storage CORS Configuration Guide

## Files Included

1. **`cors-config.json`** - Open CORS (allows all origins) - Use for development
2. **`cors-config-production.json`** - Restricted CORS (specific domains) - Use for production

## How to Apply CORS Configuration

### Option 1: Using Google Cloud Console (Recommended)

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Select your project: `fureverhealthy-admin`
3. Navigate to **Cloud Storage** → **Buckets**
4. Click on your bucket: `fureverhealthy-admin.firebasestorage.app`
5. Go to the **Configuration** tab
6. Scroll to **CORS configuration**
7. Click **Edit**
8. Copy the contents from `cors-config.json` (or `cors-config-production.json` for production)
9. Paste into the CORS configuration editor
10. Click **Save**

### Option 2: Using gsutil Command Line

```bash
# Install gsutil if you haven't already
# https://cloud.google.com/storage/docs/gsutil_install

# Apply CORS configuration
gsutil cors set cors-config.json gs://fureverhealthy-admin.firebasestorage.app
```

### Option 3: Using Firebase CLI

```bash
# Make sure you're logged in
firebase login

# Set CORS using the JSON file
gsutil cors set cors-config.json gs://fureverhealthy-admin.firebasestorage.app
```

## Configuration Details

### Development Config (`cors-config.json`)
- **Origin**: `["*"]` - Allows all origins (for development/testing)
- **Methods**: GET, HEAD, OPTIONS
- **Max Age**: 3600 seconds (1 hour)

### Production Config (`cors-config-production.json`)
- **Origin**: Specific domains only (more secure)
- **Methods**: GET, HEAD, OPTIONS
- **Max Age**: 3600 seconds (1 hour)

**⚠️ Important**: Update the `origin` array in `cors-config-production.json` with your actual app domains before using in production.

## Verify CORS is Working

1. Open browser DevTools (F12)
2. Go to **Network** tab
3. Try to load an image from Firebase Storage
4. Check the response headers - you should see:
   - `Access-Control-Allow-Origin: *` (or your domain)
   - `Access-Control-Allow-Methods: GET, HEAD, OPTIONS`

## Troubleshooting

### Error: "No 'Access-Control-Allow-Origin' header"
- **Fix**: Make sure CORS config is saved and published
- Wait a few minutes for changes to propagate
- Clear browser cache

### Error: "CORS policy blocked"
- **Fix**: Check that your app's origin is in the `origin` array
- For development, use `cors-config.json` with `["*"]`

### Images still not loading
- **Fix**: Check Firebase Storage rules allow read access
- Verify the image URL is correct
- Check browser console for specific error messages

## Current Status

✅ You mentioned you've already configured CORS in Google Cloud to allow GET requests. 

The `cors-config.json` file provided here ensures:
- GET requests are allowed (for loading images)
- HEAD and OPTIONS are allowed (for preflight checks)
- All necessary response headers are exposed
- Cache is set to 1 hour

If you're still seeing CORS errors, double-check:
1. The CORS config was saved and published
2. You're using the correct bucket name
3. The browser cache is cleared
4. The image URLs are valid

