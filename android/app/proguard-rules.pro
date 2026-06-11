# google_mlkit_text_recognition bundles only the Latin model, but its Android
# initialize() references the optional script-recognizer option classes
# (Chinese / Devanagari / Japanese / Korean) whose models we deliberately don't
# ship. Tell R8 to ignore those missing references instead of failing the
# release build. We only use Latin (TextRecognitionScript.latin).
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
