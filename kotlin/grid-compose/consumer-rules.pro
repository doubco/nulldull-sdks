# kotlinx.serialization ships its own keep rules; the Grid models need nothing beyond them.

# Also support shrinkers that do not optimize ServiceLoader discovery.
-keepnames interface com.nulldull.grid.GridHostNormalizer
-keep class com.nulldull.grid.compose.AndroidGridHostNormalizer { public <init>(); }
