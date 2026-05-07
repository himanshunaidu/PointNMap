# PointNMap


## PointNMap (Demo App)

### How to Use as a Reference

#### Build Settings

1. Info.plist Values

Copy the keys and values from the app into the required app.

2. Header Search paths

$(SRCROOT)/PointNMapShaderTypes
$(SRCROOT)/PointNMap

3. Apple Clang - Custom Compiler Flags

Other C Flags: -DACCELERATE_NEW_LAPACK

4. Objective-C Bridging Header

Copy the header (optionally rename it) from this demo app and add to Build Settings → Swift Compiler - General → Objective-C Bridging Header.

5. MTL_HEADER_SEARCH_PATHS

$(SRCROOT)/<app_name> $(SRCROOT)/PointNMapShaderTypes


### How to Use

## PointNMapShaderTypes (Framework)

This contains the globally used Metal and Swift types that help Swift code work more seamlessly with the Metal compute shaders.
Used as a dependency for iOSPointMapper as well as the second framework.
Should be used in a similar manner in other apps. 


### How to Use

1. Add the framework to the project.

2. Add it to app target:
General → Frameworks, Libraries, and Embedded Content (Embed & Sign)

3. Also verify under Build Phases:
Target Dependencies:
     PointNMapShaderTypes
Link Binary With Libraries:
      PointNMapShaderTypes.framework
Embed Frameworks:
      PointNMapShaderTypes.framework

## PointNMapShared (Framework)

This contains the main functionality that will directly be used in the main apps.
It contains modified versions of the relevant Swift UI views (Capture View base, Annotation View base), machine learning models, feature detection and sidewalk attribute estimation components of iOSPointMapper. 
This will be used directly in AVIV ScoutRoute as well.

### How to Use

1. Add the framework to the project.

2. Add PointNMapShaderTypes framework as dependency.
General → Frameworks, Libraries, and Embedded Content (Embed & Sign)
Also verify under Build Phases:
Target Dependencies:
     PointNMapShaderTypes
Headers:
    PointNMapShaderTypes
Link Binary With Libraries:
    PointNMapShaderTypes.framework

3. Using Swift Package Manager, add DequeModule from `swift-collections` as a dependency.

4. Add it to app target:
General → Frameworks, Libraries, and Embedded Content (Embed & Sign)
Also verify under Build Phases:
Target Dependencies:
     PointNMapShaderTypes
Link Binary With Libraries:
      PointNMapShaderTypes.framework
Embed Frameworks:
      PointNMapShaderTypes.framework

5. Add the ARCameraViewBase where required. 
Note: modifications may be required to the ARCameraViewBase as there are currently no hooks to add extra functionality to it (e.g. to return the required values, such as the relevant sidewalk attributes). We can work together on this. 

