// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'colors.dart';



/// Material design text theme.
///
/// Definitions for the various typographical styles found in material design
/// (e.g., headline, caption). Rather than creating a [TextTheme] directly,
/// you can obtain an instance as [Typography.black] or [Typography.white].
///
/// To obtain the current text theme, call [Theme.of] with the current
/// [BuildContext] and read the [ThemeData.textTheme] property.
///
/// The following image [from the material design
/// specification](https://material.io/go/design-typography#typography-styles)
/// shows the recommended styles for each of the properties of a [TextTheme].
/// This image uses the `Roboto` font, which is the font used on Android. On
/// iOS, the [San Francisco
/// font](https://developer.apple.com/ios/human-interface-guidelines/visual-design/typography/)
/// is automatically used instead.
///
/// ![To see the image, visit the typography site referenced below.](https://storage.googleapis.com/material-design/publish/material_v_11/assets/0Bzhp5Z4wHba3alhXZ2pPWGk3Zjg/style_typography_styles_scale.png)
///
/// See also:
///
///  * [Typography], the class that generates [TextTheme]s appropriate for a platform.
///  * [Theme], for other aspects of a material design application that can be
///    globally adjusted, such as the color scheme.
///  * <http://material.google.com/style/typography.html>
@immutable
class TextTheme extends Diagnosticable {
  /// Creates a text theme that uses the given values.
  ///
  /// Rather than creating a new text theme, consider using [Typography.black]
  /// or [Typography.white], which implement the typography styles in the
  /// material design specification:
  ///
  /// <https://material.google.com/style/typography.html#typography-styles>
  ///
  /// If you do decide to create your own text theme, consider using one of
  /// those predefined themes as a starting point for [copyWith] or [apply].
  const TextTheme({
    this.display4,
    this.display3,
    this.display2,
    this.display1,
    this.headline,
    this.title,
    this.subhead,
    this.body2,
    this.body1,
    this.caption,
    this.button,
  });

  /// Extremely large text.
  ///
  /// The font size is 112 pixels.
  final TextStyle display4;

  /// Very, very large text.
  ///
  /// Used for the date in the dialog shown by [showDatePicker].
  final TextStyle display3;

  /// Very large text.
  final TextStyle display2;

  /// Large text.
  final TextStyle display1;

  /// Used for large text in dialogs (e.g., the month and year in the dialog
  /// shown by [showDatePicker]).
  final TextStyle headline;

  /// Used for the primary text in app bars and dialogs (e.g., [AppBar.title]
  /// and [AlertDialog.title]).
  final TextStyle title;

  /// Used for the primary text in lists (e.g., [ListTile.title]).
  final TextStyle subhead;

  /// Used for emphasizing text that would otherwise be [body1].
  final TextStyle body2;

  /// Used for the default text style for [Material].
  final TextStyle body1;

  /// Used for auxiliary text associated with images.
  final TextStyle caption;

  /// Used for text on [RaisedButton] and [FlatButton].
  final TextStyle button;

  /// Creates a copy of this text theme but with the given fields replaced with
  /// the new values.
  ///
  /// Consider using [Typography.black] or [Typography.white], which implement
  /// the typography styles in the material design specification, as a starting
  /// point.
  ///
  /// ## Sample code
  ///
  /// ```dart
  /// /// A Widget that sets the ambient theme's title text color for its
  /// /// descendants, while leaving other ambient theme attributes alone.
  /// class TitleColorThemeCopy extends StatelessWidget {
  ///   TitleColorThemeCopy({Key key, this.child, this.titleColor}) : super(key: key);
  ///
  ///   final Color titleColor;
  ///   final Widget child;
  ///
  ///   @override
  ///   Widget build(BuildContext context) {
  ///     final ThemeData theme = Theme.of(context);
  ///     return Theme(
  ///       data: theme.copyWith(
  ///         textTheme: theme.textTheme.copyWith(
  ///           title: theme.textTheme.title.copyWith(
  ///             color: titleColor,
  ///           ),
  ///         ),
  ///       ),
  ///       child: child,
  ///     );
  ///   }
  /// }
  /// ```
  ///
  /// See also:
  ///
  ///   * [merge] is used instead of [copyWith] when you want to merge all
  ///     of the fields of a TextTheme instead of individual fields.
  TextTheme copyWith({
    TextStyle display4,
    TextStyle display3,
    TextStyle display2,
    TextStyle display1,
    TextStyle headline,
    TextStyle title,
    TextStyle subhead,
    TextStyle body2,
    TextStyle body1,
    TextStyle caption,
    TextStyle button,
  }) {
    return TextTheme(
      display4: display4 ?? this.display4,
      display3: display3 ?? this.display3,
      display2: display2 ?? this.display2,
      display1: display1 ?? this.display1,
      headline: headline ?? this.headline,
      title: title ?? this.title,
      subhead: subhead ?? this.subhead,
      body2: body2 ?? this.body2,
      body1: body1 ?? this.body1,
      caption: caption ?? this.caption,
      button: button ?? this.button,
    );
  }

  /// Creates a new [TextTheme] where each text style from this object has been
  /// merged with the matching text style from the `other` object.
  ///
  /// The merging is done by calling [TextStyle.merge] on each respective pair
  /// of text styles from this and the [other] text themes and is subject to
  /// the value of [TextStyle.inherit] flag. For more details, see the
  /// documentation on [TextStyle.merge] and [TextStyle.inherit].
  ///
  /// If this theme, or the `other` theme has members that are null, then the
  /// non-null one (if any) is used. If the `other` theme is itself null, then
  /// this [TextTheme] is returned unchanged. If values in both are set, then
  /// the values are merged using [TextStyle.merge].
  ///
  /// This is particularly useful if one [TextTheme] defines one set of
  /// properties and another defines a different set, e.g. having colors
  /// defined in one text theme and font sizes in another, or when one
  /// [TextTheme] has only some fields defined, and you want to define the rest
  /// by merging it with a default theme.
  ///
  /// ## Sample code
  ///
  /// ```dart
  /// /// A Widget that sets the ambient theme's title text color for its
  /// /// descendants, while leaving other ambient theme attributes alone.
  /// class TitleColorTheme extends StatelessWidget {
  ///   TitleColorTheme({Key key, this.child, this.titleColor}) : super(key: key);
  ///
  ///   final Color titleColor;
  ///   final Widget child;
  ///
  ///   @override
  ///   Widget build(BuildContext context) {
  ///     ThemeData theme = Theme.of(context);
  ///     // This partialTheme is incomplete: it only has the title style
  ///     // defined. Just replacing theme.textTheme with partialTheme would
  ///     // set the title, but everything else would be null. This isn't very
  ///     // useful, so merge it with the existing theme to keep all of the
  ///     // preexisting definitions for the other styles.
  ///     TextTheme partialTheme = TextTheme(title: TextStyle(color: titleColor));
  ///     theme = theme.copyWith(textTheme: theme.textTheme.merge(partialTheme));
  ///     return Theme(data: theme, child: child);
  ///   }
  /// }
  /// ```
  ///
  /// See also:
  ///
  ///   * [copyWith] is used instead of [merge] when you wish to override
  ///     individual fields in the [TextTheme] instead of merging all of the
  ///     fields of two [TextTheme]s.
  TextTheme merge(TextTheme other) {
    if (other == null)
      return this;
    return copyWith(
      display4: display4?.merge(other.display4) ?? other.display4,
      display3: display3?.merge(other.display3) ?? other.display3,
      display2: display2?.merge(other.display2) ?? other.display2,
      display1: display1?.merge(other.display1) ?? other.display1,
      headline: headline?.merge(other.headline) ?? other.headline,
      title: title?.merge(other.title) ?? other.title,
      subhead: subhead?.merge(other.subhead) ?? other.subhead,
      body2: body2?.merge(other.body2) ?? other.body2,
      body1: body1?.merge(other.body1) ?? other.body1,
      caption: caption?.merge(other.caption) ?? other.caption,
      button: button?.merge(other.button) ?? other.button,
    );
  }

  /// Creates a copy of this text theme but with the given field replaced in
  /// each of the individual text styles.
  ///
  /// The `displayColor` is applied to [display4], [display3], [display2],
  /// [display1], and [caption]. The `bodyColor` is applied to the remaining
  /// text styles.
  ///
  /// Consider using [Typography.black] or [Typography.white], which implement
  /// the typography styles in the material design specification, as a starting
  /// point.
  TextTheme apply({
    String fontFamily,
    double fontSizeFactor = 1.0,
    double fontSizeDelta = 0.0,
    Color displayColor,
    Color bodyColor,
    TextDecoration decoration,
    Color decorationColor,
    TextDecorationStyle decorationStyle,
  }) {
    return TextTheme(
      display4: display4.apply(
        color: displayColor,
        decoration: decoration,
        decorationColor: decorationColor,
        decorationStyle: decorationStyle,
        fontFamily: fontFamily,
        fontSizeFactor: fontSizeFactor,
        fontSizeDelta: fontSizeDelta,
      ),
      display3: display3.apply(
        color: displayColor,
        decoration: decoration,
        decorationColor: decorationColor,
        decorationStyle: decorationStyle,
        fontFamily: fontFamily,
        fontSizeFactor: fontSizeFactor,
        fontSizeDelta: fontSizeDelta,
      ),
      display2: display2.apply(
        color: displayColor,
        decoration: decoration,
        decorationColor: decorationColor,
        decorationStyle: decorationStyle,
        fontFamily: fontFamily,
        fontSizeFactor: fontSizeFactor,
        fontSizeDelta: fontSizeDelta,
      ),
      display1: display1.apply(
        color: displayColor,
        decoration: decoration,
        decorationColor: decorationColor,
        decorationStyle: decorationStyle,
        fontFamily: fontFamily,
        fontSizeFactor: fontSizeFactor,
        fontSizeDelta: fontSizeDelta,
      ),
      headline: headline.apply(
        color: bodyColor,
        decoration: decoration,
        decorationColor: decorationColor,
        decorationStyle: decorationStyle,
        fontFamily: fontFamily,
        fontSizeFactor: fontSizeFactor,
        fontSizeDelta: fontSizeDelta,
      ),
      title: title.apply(
        color: bodyColor,
        decoration: decoration,
        decorationColor: decorationColor,
        decorationStyle: decorationStyle,
        fontFamily: fontFamily,
        fontSizeFactor: fontSizeFactor,
        fontSizeDelta: fontSizeDelta,
      ),
      subhead: subhead.apply(
        color: bodyColor,
        decoration: decoration,
        decorationColor: decorationColor,
        decorationStyle: decorationStyle,
        fontFamily: fontFamily,
        fontSizeFactor: fontSizeFactor,
        fontSizeDelta: fontSizeDelta,
      ),
      body2: body2.apply(
        color: bodyColor,
        decoration: decoration,
        decorationColor: decorationColor,
        decorationStyle: decorationStyle,
        fontFamily: fontFamily,
        fontSizeFactor: fontSizeFactor,
        fontSizeDelta: fontSizeDelta,
      ),
      body1: body1.apply(
        color: bodyColor,
        decoration: decoration,
        decorationColor: decorationColor,
        decorationStyle: decorationStyle,
        fontFamily: fontFamily,
        fontSizeFactor: fontSizeFactor,
        fontSizeDelta: fontSizeDelta,
      ),
      caption: caption.apply(
        color: displayColor,
        decoration: decoration,
        decorationColor: decorationColor,
        decorationStyle: decorationStyle,
        fontFamily: fontFamily,
        fontSizeFactor: fontSizeFactor,
        fontSizeDelta: fontSizeDelta,
      ),
      button: button.apply(
        color: bodyColor,
        decoration: decoration,
        decorationColor: decorationColor,
        decorationStyle: decorationStyle,
        fontFamily: fontFamily,
        fontSizeFactor: fontSizeFactor,
        fontSizeDelta: fontSizeDelta,
      ),
    );
  }

  /// Linearly interpolate between two text themes.
  ///
  /// The arguments must not be null.
  ///
  /// The `t` argument represents position on the timeline, with 0.0 meaning
  /// that the interpolation has not started, returning `a` (or something
  /// equivalent to `a`), 1.0 meaning that the interpolation has finished,
  /// returning `b` (or something equivalent to `b`), and values in between
  /// meaning that the interpolation is at the relevant point on the timeline
  /// between `a` and `b`. The interpolation can be extrapolated beyond 0.0 and
  /// 1.0, so negative values and values greater than 1.0 are valid (and can
  /// easily be generated by curves such as [Curves.elasticInOut]).
  ///
  /// Values for `t` are usually obtained from an [Animation<double>], such as
  /// an [AnimationController].
  static TextTheme lerp(TextTheme a, TextTheme b, double t) {
    assert(a != null);
    assert(b != null);
    assert(t != null);
    return TextTheme(
      display4: TextStyle.lerp(a.display4, b.display4, t),
      display3: TextStyle.lerp(a.display3, b.display3, t),
      display2: TextStyle.lerp(a.display2, b.display2, t),
      display1: TextStyle.lerp(a.display1, b.display1, t),
      headline: TextStyle.lerp(a.headline, b.headline, t),
      title: TextStyle.lerp(a.title, b.title, t),
      subhead: TextStyle.lerp(a.subhead, b.subhead, t),
      body2: TextStyle.lerp(a.body2, b.body2, t),
      body1: TextStyle.lerp(a.body1, b.body1, t),
      caption: TextStyle.lerp(a.caption, b.caption, t),
      button: TextStyle.lerp(a.button, b.button, t),
    );
  }

  @override
  bool operator ==(dynamic other) {
    if (identical(this, other))
      return true;
    if (other.runtimeType != runtimeType)
      return false;
    final TextTheme typedOther = other;
    return display4 == typedOther.display4 &&
           display3 == typedOther.display3 &&
           display2 == typedOther.display2 &&
           display1 == typedOther.display1 &&
           headline == typedOther.headline &&
           title == typedOther.title &&
           subhead == typedOther.subhead &&
           body2 == typedOther.body2 &&
           body1 == typedOther.body1 &&
           caption == typedOther.caption &&
           button == typedOther.button;
  }

  @override
  int get hashCode {
    return hashValues(
      display4,
      display3,
      display2,
      display1,
      headline,
      title,
      subhead,
      body2,
      body1,
      caption,
      button,
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    final TextTheme defaultTheme = Typography(platform: defaultTargetPlatform).black;
    properties.add(DiagnosticsProperty<TextStyle>('display4', display4, defaultValue: defaultTheme.display4));
    properties.add(DiagnosticsProperty<TextStyle>('display3', display3, defaultValue: defaultTheme.display3));
    properties.add(DiagnosticsProperty<TextStyle>('display2', display2, defaultValue: defaultTheme.display2));
    properties.add(DiagnosticsProperty<TextStyle>('display1', display1, defaultValue: defaultTheme.display1));
    properties.add(DiagnosticsProperty<TextStyle>('headline', headline, defaultValue: defaultTheme.headline));
    properties.add(DiagnosticsProperty<TextStyle>('title', title, defaultValue: defaultTheme.title));
    properties.add(DiagnosticsProperty<TextStyle>('subhead', subhead, defaultValue: defaultTheme.subhead));
    properties.add(DiagnosticsProperty<TextStyle>('body2', body2, defaultValue: defaultTheme.body2));
    properties.add(DiagnosticsProperty<TextStyle>('body1', body1, defaultValue: defaultTheme.body1));
    properties.add(DiagnosticsProperty<TextStyle>('caption', caption, defaultValue: defaultTheme.caption));
    properties.add(DiagnosticsProperty<TextStyle>('button', button, defaultValue: defaultTheme.button));
  }
}

/// The two material design text themes.
///
/// Material design defines two text themes: [black] and [white]. The black
/// text theme, which uses dark glyphs, is used on light backgrounds in light
/// themes. The white text theme, which uses light glyphs, is used in dark
/// themes and on dark backgrounds in light themes.
///
/// To obtain the current text theme, call [Theme.of] with the current
/// [BuildContext] and read the [ThemeData.textTheme] property.
///
/// See also:
///
///  * [TextTheme], which shows what the text styles in a theme look like.
///  * [Theme], for other aspects of a material design application that can be
///    globally adjusted, such as the color scheme.
///  * <http://material.google.com/style/typography.html>
class Typography {
  /// Creates the default typography for the specified platform.
  factory Typography({@required TargetPlatform platform}) {
    assert(platform != null);
    switch (platform) {
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
        return const Typography._(
          _MaterialTextColorThemes.blackMountainView,
          _MaterialTextColorThemes.whiteMountainView,
        );
      case TargetPlatform.iOS:
        return const Typography._(
          _MaterialTextColorThemes.blackCupertino,
          _MaterialTextColorThemes.whiteCupertino,
        );
    }
    return null;
  }

  const Typography._(this.black, this.white);

  /// A material design text theme with dark glyphs.
  final TextTheme black;

  /// A material design text theme with light glyphs.
  final TextTheme white;
}

/// Provides default text theme colors compliant with the Material Design
/// specification.
///
/// The geometric font properties are missing in these color themes. App are
/// expected to use [Theme.of] to get [TextTheme] objects fully populated with
/// font properties.
///
/// See also: https://material.io/go/design-typography
// TODO(yjbanov): implement font fallback (see "Font stack" at https://material.io/go/design-typography)
class _MaterialTextColorThemes {
  static const TextTheme blackMountainView = TextTheme(
    display4: TextStyle(debugLabel: 'blackMountainView display4', fontFamily: 'Roboto',         inherit: true, color: Colors.black54, decoration: TextDecoration.none),
    display3: TextStyle(debugLabel: 'blackMountainView display3', fontFamily: 'Roboto',         inherit: true, color: Colors.black54, decoration: TextDecoration.none),
    display2: TextStyle(debugLabel: 'blackMountainView display2', fontFamily: 'Roboto',         inherit: true, color: Colors.black54, decoration: TextDecoration.none),
    display1: TextStyle(debugLabel: 'blackMountainView display1', fontFamily: 'Roboto',         inherit: true, color: Colors.black54, decoration: TextDecoration.none),
    headline: TextStyle(debugLabel: 'blackMountainView headline', fontFamily: 'Roboto',         inherit: true, color: Colors.black87, decoration: TextDecoration.none),
    title   : TextStyle(debugLabel: 'blackMountainView title',    fontFamily: 'Roboto',         inherit: true, color: Colors.black87, decoration: TextDecoration.none),
    subhead : TextStyle(debugLabel: 'blackMountainView subhead',  fontFamily: 'Roboto',         inherit: true, color: Colors.black87, decoration: TextDecoration.none),
    body2   : TextStyle(debugLabel: 'blackMountainView body2',    fontFamily: 'Roboto',         inherit: true, color: Colors.black87, decoration: TextDecoration.none),
    body1   : TextStyle(debugLabel: 'blackMountainView body1',    fontFamily: 'Roboto',         inherit: true, color: Colors.black87, decoration: TextDecoration.none),
    caption : TextStyle(debugLabel: 'blackMountainView caption',  fontFamily: 'Roboto',         inherit: true, color: Colors.black54, decoration: TextDecoration.none),
    button  : TextStyle(debugLabel: 'blackMountainView button',   fontFamily: 'Roboto',         inherit: true, color: Colors.black87, decoration: TextDecoration.none),
  );

  static const TextTheme whiteMountainView = TextTheme(
    display4: TextStyle(debugLabel: 'whiteMountainView display4', fontFamily: 'Roboto',         inherit: true, color: Colors.white70, decoration: TextDecoration.none),
    display3: TextStyle(debugLabel: 'whiteMountainView display3', fontFamily: 'Roboto',         inherit: true, color: Colors.white70, decoration: TextDecoration.none),
    display2: TextStyle(debugLabel: 'whiteMountainView display2', fontFamily: 'Roboto',         inherit: true, color: Colors.white70, decoration: TextDecoration.none),
    display1: TextStyle(debugLabel: 'whiteMountainView display1', fontFamily: 'Roboto',         inherit: true, color: Colors.white70, decoration: TextDecoration.none),
    headline: TextStyle(debugLabel: 'whiteMountainView headline', fontFamily: 'Roboto',         inherit: true, color: Colors.white,   decoration: TextDecoration.none),
    title   : TextStyle(debugLabel: 'whiteMountainView title',    fontFamily: 'Roboto',         inherit: true, color: Colors.white,   decoration: TextDecoration.none),
    subhead : TextStyle(debugLabel: 'whiteMountainView subhead',  fontFamily: 'Roboto',         inherit: true, color: Colors.white,   decoration: TextDecoration.none),
    body2   : TextStyle(debugLabel: 'whiteMountainView body2',    fontFamily: 'Roboto',         inherit: true, color: Colors.white,   decoration: TextDecoration.none),
    body1   : TextStyle(debugLabel: 'whiteMountainView body1',    fontFamily: 'Roboto',         inherit: true, color: Colors.white,   decoration: TextDecoration.none),
    caption : TextStyle(debugLabel: 'whiteMountainView caption',  fontFamily: 'Roboto',         inherit: true, color: Colors.white70, decoration: TextDecoration.none),
    button  : TextStyle(debugLabel: 'whiteMountainView button',   fontFamily: 'Roboto',         inherit: true, color: Colors.white,   decoration: TextDecoration.none),
  );

  static const TextTheme blackCupertino = TextTheme(
    display4: TextStyle(debugLabel: 'blackCupertino display4', fontFamily: '.SF UI Display', inherit: true, color: Colors.black54, decoration: TextDecoration.none),
    display3: TextStyle(debugLabel: 'blackCupertino display3', fontFamily: '.SF UI Display', inherit: true, color: Colors.black54, decoration: TextDecoration.none),
    display2: TextStyle(debugLabel: 'blackCupertino display2', fontFamily: '.SF UI Display', inherit: true, color: Colors.black54, decoration: TextDecoration.none),
    display1: TextStyle(debugLabel: 'blackCupertino display1', fontFamily: '.SF UI Display', inherit: true, color: Colors.black54, decoration: TextDecoration.none),
    headline: TextStyle(debugLabel: 'blackCupertino headline', fontFamily: '.SF UI Display', inherit: true, color: Colors.black87, decoration: TextDecoration.none),
    title   : TextStyle(debugLabel: 'blackCupertino title',    fontFamily: '.SF UI Display', inherit: true, color: Colors.black87, decoration: TextDecoration.none),
    subhead : TextStyle(debugLabel: 'blackCupertino subhead',  fontFamily: '.SF UI Text',    inherit: true, color: Colors.black87, decoration: TextDecoration.none),
    body2   : TextStyle(debugLabel: 'blackCupertino body2',    fontFamily: '.SF UI Text',    inherit: true, color: Colors.black87, decoration: TextDecoration.none),
    body1   : TextStyle(debugLabel: 'blackCupertino body1',    fontFamily: '.SF UI Text',    inherit: true, color: Colors.black87, decoration: TextDecoration.none),
    caption : TextStyle(debugLabel: 'blackCupertino caption',  fontFamily: '.SF UI Text',    inherit: true, color: Colors.black54, decoration: TextDecoration.none),
    button  : TextStyle(debugLabel: 'blackCupertino button',   fontFamily: '.SF UI Text',    inherit: true, color: Colors.black87, decoration: TextDecoration.none),
  );

  static const TextTheme whiteCupertino = TextTheme(
    display4: TextStyle(debugLabel: 'whiteCupertino display4', fontFamily: '.SF UI Display', inherit: true, color: Colors.white70, decoration: TextDecoration.none),
    display3: TextStyle(debugLabel: 'whiteCupertino display3', fontFamily: '.SF UI Display', inherit: true, color: Colors.white70, decoration: TextDecoration.none),
    display2: TextStyle(debugLabel: 'whiteCupertino display2', fontFamily: '.SF UI Display', inherit: true, color: Colors.white70, decoration: TextDecoration.none),
    display1: TextStyle(debugLabel: 'whiteCupertino display1', fontFamily: '.SF UI Display', inherit: true, color: Colors.white70, decoration: TextDecoration.none),
    headline: TextStyle(debugLabel: 'whiteCupertino headline', fontFamily: '.SF UI Display', inherit: true, color: Colors.white,   decoration: TextDecoration.none),
    title   : TextStyle(debugLabel: 'whiteCupertino title',    fontFamily: '.SF UI Display', inherit: true, color: Colors.white,   decoration: TextDecoration.none),
    subhead : TextStyle(debugLabel: 'whiteCupertino subhead',  fontFamily: '.SF UI Text',    inherit: true, color: Colors.white,   decoration: TextDecoration.none),
    body2   : TextStyle(debugLabel: 'whiteCupertino body2',    fontFamily: '.SF UI Text',    inherit: true, color: Colors.white,   decoration: TextDecoration.none),
    body1   : TextStyle(debugLabel: 'whiteCupertino body1',    fontFamily: '.SF UI Text',    inherit: true, color: Colors.white,   decoration: TextDecoration.none),
    caption : TextStyle(debugLabel: 'whiteCupertino caption',  fontFamily: '.SF UI Text',    inherit: true, color: Colors.white70, decoration: TextDecoration.none),
    button  : TextStyle(debugLabel: 'whiteCupertino button',   fontFamily: '.SF UI Text',    inherit: true, color: Colors.white,   decoration: TextDecoration.none),
  );
}

/// Defines text geometries for the three language categories defined in
/// https://material.io/go/design-typography.
class MaterialTextGeometry {
  /// The name of the English-like script category.
  static const String englishLikeCategory = 'English-like';

  /// The name of the dense script category.
  static const String denseCategory = 'dense';

  /// The name of the tall script category.
  static const String tallCategory = 'tall';

  /// The mapping from script category names to text themes.
  static const Map<String, TextTheme> _categoryToTextTheme = <String, TextTheme>{
    englishLikeCategory: englishLike,
    denseCategory: dense,
    tallCategory: tall,
  };

  /// Looks up text geometry corresponding to the given [scriptCategoryName].
  ///
  /// Most apps would not call this method directly, but rather call [Theme.of]
  /// and use the [TextTheme] fields of the returned [ThemeData] object.
  ///
  /// [scriptCategoryName] must be one of [englishLikeCategory], [denseCategory]
  /// and [tallCategory].
  ///
  /// See also:
  ///
  ///  * [DefaultMaterialLocalizations.localTextGeometry], which uses this
  ///    method to look-up text geometry for the current locale.
  static TextTheme forScriptCategory(String scriptCategoryName) => _categoryToTextTheme[scriptCategoryName];

  /// Defines text geometry for English-like scripts, such as English, French, Russian, etc.
  static const TextTheme englishLike = TextTheme(
    display4: TextStyle(debugLabel: 'englishLike display4', inherit: false, fontSize: 112.0, fontWeight: FontWeight.w100, textBaseline: TextBaseline.alphabetic),
    display3: TextStyle(debugLabel: 'englishLike display3', inherit: false, fontSize:  56.0, fontWeight: FontWeight.w400, textBaseline: TextBaseline.alphabetic),
    display2: TextStyle(debugLabel: 'englishLike display2', inherit: false, fontSize:  45.0, fontWeight: FontWeight.w400, textBaseline: TextBaseline.alphabetic),
    display1: TextStyle(debugLabel: 'englishLike display1', inherit: false, fontSize:  34.0, fontWeight: FontWeight.w400, textBaseline: TextBaseline.alphabetic),
    headline: TextStyle(debugLabel: 'englishLike headline', inherit: false, fontSize:  24.0, fontWeight: FontWeight.w400, textBaseline: TextBaseline.alphabetic),
    title   : TextStyle(debugLabel: 'englishLike title',    inherit: false, fontSize:  20.0, fontWeight: FontWeight.w500, textBaseline: TextBaseline.alphabetic),
    subhead : TextStyle(debugLabel: 'englishLike subhead',  inherit: false, fontSize:  16.0, fontWeight: FontWeight.w400, textBaseline: TextBaseline.alphabetic),
    body2   : TextStyle(debugLabel: 'englishLike body2',    inherit: false, fontSize:  14.0, fontWeight: FontWeight.w500, textBaseline: TextBaseline.alphabetic),
    body1   : TextStyle(debugLabel: 'englishLike body1',    inherit: false, fontSize:  14.0, fontWeight: FontWeight.w400, textBaseline: TextBaseline.alphabetic),
    caption : TextStyle(debugLabel: 'englishLike caption',  inherit: false, fontSize:  12.0, fontWeight: FontWeight.w400, textBaseline: TextBaseline.alphabetic),
    button  : TextStyle(debugLabel: 'englishLike button',   inherit: false, fontSize:  14.0, fontWeight: FontWeight.w500, textBaseline: TextBaseline.alphabetic),
  );

  /// Defines text geometry for dense scripts, such as Chinese, Japanese, Korean, etc.
  static const TextTheme dense = TextTheme(
    display4: TextStyle(debugLabel: 'dense display4', inherit: false, fontSize: 112.0, fontWeight: FontWeight.w100, textBaseline: TextBaseline.ideographic),
    display3: TextStyle(debugLabel: 'dense display3', inherit: false, fontSize:  56.0, fontWeight: FontWeight.w400, textBaseline: TextBaseline.ideographic),
    display2: TextStyle(debugLabel: 'dense display2', inherit: false, fontSize:  45.0, fontWeight: FontWeight.w400, textBaseline: TextBaseline.ideographic),
    display1: TextStyle(debugLabel: 'dense display1', inherit: false, fontSize:  34.0, fontWeight: FontWeight.w400, textBaseline: TextBaseline.ideographic),
    headline: TextStyle(debugLabel: 'dense headline', inherit: false, fontSize:  24.0, fontWeight: FontWeight.w400, textBaseline: TextBaseline.ideographic),
    title   : TextStyle(debugLabel: 'dense title',    inherit: false, fontSize:  21.0, fontWeight: FontWeight.w500, textBaseline: TextBaseline.ideographic),
    subhead : TextStyle(debugLabel: 'dense subhead',  inherit: false, fontSize:  17.0, fontWeight: FontWeight.w400, textBaseline: TextBaseline.ideographic),
    body2   : TextStyle(debugLabel: 'dense body2',    inherit: false, fontSize:  15.0, fontWeight: FontWeight.w500, textBaseline: TextBaseline.ideographic),
    body1   : TextStyle(debugLabel: 'dense body1',    inherit: false, fontSize:  15.0, fontWeight: FontWeight.w400, textBaseline: TextBaseline.ideographic),
    caption : TextStyle(debugLabel: 'dense caption',  inherit: false, fontSize:  13.0, fontWeight: FontWeight.w400, textBaseline: TextBaseline.ideographic),
    button  : TextStyle(debugLabel: 'dense button',   inherit: false, fontSize:  15.0, fontWeight: FontWeight.w500, textBaseline: TextBaseline.ideographic),
  );

  /// Defines text geometry for tall scripts, such as Farsi, Hindi, Thai, etc.
  static const TextTheme tall = TextTheme(
    display4: TextStyle(debugLabel: 'tall display4', inherit: false, fontSize: 112.0, fontWeight: FontWeight.w400, textBaseline: TextBaseline.alphabetic),
    display3: TextStyle(debugLabel: 'tall display3', inherit: false, fontSize:  56.0, fontWeight: FontWeight.w400, textBaseline: TextBaseline.alphabetic),
    display2: TextStyle(debugLabel: 'tall display2', inherit: false, fontSize:  45.0, fontWeight: FontWeight.w400, textBaseline: TextBaseline.alphabetic),
    display1: TextStyle(debugLabel: 'tall display1', inherit: false, fontSize:  34.0, fontWeight: FontWeight.w400, textBaseline: TextBaseline.alphabetic),
    headline: TextStyle(debugLabel: 'tall headline', inherit: false, fontSize:  24.0, fontWeight: FontWeight.w400, textBaseline: TextBaseline.alphabetic),
    title   : TextStyle(debugLabel: 'tall title',    inherit: false, fontSize:  21.0, fontWeight: FontWeight.w700, textBaseline: TextBaseline.alphabetic),
    subhead : TextStyle(debugLabel: 'tall subhead',  inherit: false, fontSize:  17.0, fontWeight: FontWeight.w400, textBaseline: TextBaseline.alphabetic),
    body2   : TextStyle(debugLabel: 'tall body2',    inherit: false, fontSize:  15.0, fontWeight: FontWeight.w700, textBaseline: TextBaseline.alphabetic),
    body1   : TextStyle(debugLabel: 'tall body1',    inherit: false, fontSize:  15.0, fontWeight: FontWeight.w400, textBaseline: TextBaseline.alphabetic),
    caption : TextStyle(debugLabel: 'tall caption',  inherit: false, fontSize:  13.0, fontWeight: FontWeight.w400, textBaseline: TextBaseline.alphabetic),
    button  : TextStyle(debugLabel: 'tall button',   inherit: false, fontSize:  15.0, fontWeight: FontWeight.w700, textBaseline: TextBaseline.alphabetic),
  );
}
