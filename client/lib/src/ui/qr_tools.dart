part of '../../main.dart';

const _sharedQrCardWidth = 1200.0;
const _sharedQrCardHeight = 1600.0;

enum _QrCardTheme { simple, blueBusiness, blackGold, plainQr, horizontalCard }

class _QrCardStyle {
  const _QrCardStyle({
    this.showAvatar = true,
    this.showTitle = true,
    this.theme = _QrCardTheme.simple,
    this.centerMode = _QrCenterMode.avatar,
  });

  final bool showAvatar;
  final bool showTitle;
  final _QrCardTheme theme;
  final _QrCenterMode centerMode;

  _QrCardStyle copyWith({
    bool? showAvatar,
    bool? showTitle,
    _QrCardTheme? theme,
    _QrCenterMode? centerMode,
  }) {
    return _QrCardStyle(
      showAvatar: showAvatar ?? this.showAvatar,
      showTitle: showTitle ?? this.showTitle,
      theme: theme ?? this.theme,
      centerMode: centerMode ?? this.centerMode,
    );
  }
}

enum _QrCenterMode { none, avatar, logo }

class _QrCardPalette {
  const _QrCardPalette({
    required this.background,
    required this.card,
    required this.primary,
    required this.onCard,
    required this.muted,
    required this.border,
    required this.qrBackground,
    required this.qrForeground,
  });

  final Color background;
  final Color card;
  final Color primary;
  final Color onCard;
  final Color muted;
  final Color border;
  final Color qrBackground;
  final Color qrForeground;
}

_QrCardPalette _qrPaletteFor(_QrCardTheme theme) {
  switch (theme) {
    case _QrCardTheme.simple:
      return const _QrCardPalette(
        background: Color(0xFFF5F7FB),
        card: Colors.white,
        primary: Color(0xFF246BFE),
        onCard: Color(0xFF172033),
        muted: Color(0xFF667085),
        border: Color(0xFFE2E8F0),
        qrBackground: Colors.white,
        qrForeground: Color(0xFF111827),
      );
    case _QrCardTheme.blueBusiness:
      return const _QrCardPalette(
        background: Color(0xFFEAF3FF),
        card: Color(0xFFFFFFFF),
        primary: Color(0xFF0B5CAD),
        onCard: Color(0xFF0B1F36),
        muted: Color(0xFF42627D),
        border: Color(0xFFB6D4F0),
        qrBackground: Color(0xFFFFFFFF),
        qrForeground: Color(0xFF08233F),
      );
    case _QrCardTheme.blackGold:
      return const _QrCardPalette(
        background: Color(0xFF11100D),
        card: Color(0xFF1C1812),
        primary: Color(0xFFD9B35F),
        onCard: Color(0xFFFFF8E8),
        muted: Color(0xFFE3CF9C),
        border: Color(0xFF6E5625),
        qrBackground: Color(0xFFFFF8E8),
        qrForeground: Color(0xFF18140E),
      );
    case _QrCardTheme.plainQr:
      return const _QrCardPalette(
        background: Color(0xFFFFFFFF),
        card: Color(0xFFFFFFFF),
        primary: Color(0xFF111827),
        onCard: Color(0xFF111827),
        muted: Color(0xFF4B5563),
        border: Color(0xFFE5E7EB),
        qrBackground: Color(0xFFFFFFFF),
        qrForeground: Color(0xFF111827),
      );
    case _QrCardTheme.horizontalCard:
      return const _QrCardPalette(
        background: Color(0xFFF7F4EF),
        card: Color(0xFFFFFFFF),
        primary: Color(0xFF1F8A70),
        onCard: Color(0xFF18231F),
        muted: Color(0xFF5C6B63),
        border: Color(0xFFC9D8CE),
        qrBackground: Color(0xFFFFFFFF),
        qrForeground: Color(0xFF10251E),
      );
  }
}

String _qrThemeLabel(CsacStrings strings, _QrCardTheme theme) {
  switch (theme) {
    case _QrCardTheme.simple:
      return strings.text('Simple');
    case _QrCardTheme.blueBusiness:
      return strings.text('Blue business');
    case _QrCardTheme.blackGold:
      return strings.text('Black gold');
    case _QrCardTheme.plainQr:
      return strings.text('Plain QR');
    case _QrCardTheme.horizontalCard:
      return strings.text('Horizontal card');
  }
}

IconData _qrThemeIcon(_QrCardTheme theme) {
  switch (theme) {
    case _QrCardTheme.simple:
      return Icons.crop_square;
    case _QrCardTheme.blueBusiness:
      return Icons.business_center_outlined;
    case _QrCardTheme.blackGold:
      return Icons.workspace_premium_outlined;
    case _QrCardTheme.plainQr:
      return Icons.qr_code_2;
    case _QrCardTheme.horizontalCard:
      return Icons.view_agenda_outlined;
  }
}

String _qrCenterModeLabel(CsacStrings strings, _QrCenterMode mode) {
  switch (mode) {
    case _QrCenterMode.none:
      return strings.text('None');
    case _QrCenterMode.avatar:
      return strings.text('Avatar');
    case _QrCenterMode.logo:
      return strings.text('Logo');
  }
}

Future<Uint8List> _renderCsacQrPng(
  String link, {
  String title = '',
  String subtitle = '',
  String avatarUrl = '',
  _QrCardStyle style = const _QrCardStyle(),
}) async {
  final avatarImage = style.centerMode == _QrCenterMode.avatar
      ? await _loadQrAvatarImage(avatarUrl)
      : null;
  final cardSize = _qrCardSizeFor(style.theme);
  final painter = QrPainter(
    data: link,
    version: QrVersions.auto,
    errorCorrectionLevel: QrErrorCorrectLevel.M,
    gapless: true,
    eyeStyle: QrEyeStyle(
      eyeShape: QrEyeShape.square,
      color: _qrPaletteFor(style.theme).qrForeground,
    ),
    dataModuleStyle: QrDataModuleStyle(
      dataModuleShape: QrDataModuleShape.square,
      color: _qrPaletteFor(style.theme).qrForeground,
    ),
  );
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  _paintQrCard(
    canvas,
    painter: painter,
    link: link,
    title: title,
    subtitle: subtitle,
    avatarImage: avatarImage,
    style: style,
    cardSize: cardSize,
  );
  final image = await recorder.endRecording().toImage(
    cardSize.width.toInt(),
    cardSize.height.toInt(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  avatarImage?.dispose();
  return data?.buffer.asUint8List() ?? Uint8List(0);
}

Size _qrCardSizeFor(_QrCardTheme theme) {
  switch (theme) {
    case _QrCardTheme.horizontalCard:
      return const Size(1600, 960);
    case _QrCardTheme.plainQr:
      return const Size(1080, 1080);
    case _QrCardTheme.simple:
    case _QrCardTheme.blueBusiness:
    case _QrCardTheme.blackGold:
      return const Size(_sharedQrCardWidth, _sharedQrCardHeight);
  }
}

Future<void> _shareCsacQrPng(
  BuildContext context, {
  required String link,
  required String title,
  required String subject,
  required String fileName,
  String cardTitle = '',
  String cardSubtitle = '',
  String avatarUrl = '',
  _QrCardStyle style = const _QrCardStyle(),
}) async {
  final renderObject = context.findRenderObject();
  final box = renderObject is RenderBox ? renderObject : null;
  final bytes = await _renderCsacQrPng(
    link,
    title: cardTitle,
    subtitle: cardSubtitle,
    avatarUrl: avatarUrl,
    style: style,
  );
  if (bytes.isEmpty) {
    throw StateError('QR image is empty');
  }
  await SharePlus.instance.share(
    ShareParams(
      title: title,
      subject: subject,
      text: link,
      files: [XFile.fromData(bytes, name: fileName, mimeType: 'image/png')],
      sharePositionOrigin: box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size,
    ),
  );
}

void _paintPlainQrCard(
  Canvas canvas, {
  required QrPainter painter,
  required Size cardSize,
  required _QrCardPalette palette,
  required ui.Image? avatarImage,
  required String title,
  required _QrCardStyle style,
}) {
  final qrOuterRect = RRect.fromRectAndRadius(
    Rect.fromCenter(
      center: Offset(cardSize.width / 2, cardSize.height / 2),
      width: 900,
      height: 900,
    ),
    const Radius.circular(28),
  );
  canvas.drawRRect(qrOuterRect, Paint()..color = palette.qrBackground);
  final qrRect = qrOuterRect.outerRect.deflate(42);
  canvas.save();
  canvas.translate(qrRect.left, qrRect.top);
  painter.paint(canvas, qrRect.size);
  canvas.restore();
  _paintQrCenterMark(
    canvas,
    center: qrRect.center,
    palette: palette,
    avatarImage: avatarImage,
    fallbackText: title,
    style: style,
    size: 104,
  );
}

void _paintHorizontalQrCard(
  Canvas canvas, {
  required QrPainter painter,
  required Size cardSize,
  required _QrCardPalette palette,
  required ui.Image? avatarImage,
  required String title,
  required String subtitle,
  required _QrCardStyle style,
  required String link,
}) {
  final left = 180.0;
  final centerY = cardSize.height / 2;
  if (style.showAvatar) {
    _paintQrAvatar(
      canvas,
      center: Offset(left + 86, centerY - 140),
      radius: 86,
      palette: palette,
      avatarImage: avatarImage,
      fallbackText: title,
    );
  }
  var textTop = style.showAvatar ? centerY - 12 : centerY - 128;
  if (style.showTitle && title.trim().isNotEmpty) {
    textTop += _paintLeftParagraph(
      canvas,
      title.trim(),
      Offset(left, textTop),
      maxWidth: 600,
      style: TextStyle(
        color: palette.onCard,
        fontSize: 58,
        fontWeight: FontWeight.w900,
        height: 1.12,
      ),
      maxLines: 2,
    );
    if (subtitle.trim().isNotEmpty) {
      textTop += 18;
      textTop += _paintLeftParagraph(
        canvas,
        subtitle.trim(),
        Offset(left, textTop),
        maxWidth: 560,
        style: TextStyle(
          color: palette.muted,
          fontSize: 30,
          fontWeight: FontWeight.w600,
          height: 1.2,
        ),
        maxLines: 1,
      );
    }
  }
  _paintLeftParagraph(
    canvas,
    link,
    Offset(left, cardSize.height - 214),
    maxWidth: 600,
    style: TextStyle(
      color: palette.muted,
      fontSize: 24,
      fontWeight: FontWeight.w500,
      height: 1.25,
    ),
    maxLines: 2,
  );

  final qrOuterRect = RRect.fromRectAndRadius(
    Rect.fromCenter(
      center: Offset(cardSize.width - 452, cardSize.height / 2),
      width: 640,
      height: 640,
    ),
    const Radius.circular(42),
  );
  canvas.drawRRect(qrOuterRect, Paint()..color = palette.qrBackground);
  canvas.drawRRect(
    qrOuterRect,
    Paint()
      ..color = palette.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2,
  );
  final qrRect = qrOuterRect.outerRect.deflate(46);
  canvas.save();
  canvas.translate(qrRect.left, qrRect.top);
  painter.paint(canvas, qrRect.size);
  canvas.restore();
  _paintQrCenterMark(
    canvas,
    center: qrRect.center,
    palette: palette,
    avatarImage: avatarImage,
    fallbackText: title,
    style: style,
    size: 76,
  );
}

void _paintQrCenterMark(
  Canvas canvas, {
  required Offset center,
  required _QrCardPalette palette,
  required ui.Image? avatarImage,
  required String fallbackText,
  required _QrCardStyle style,
  double size = 132,
}) {
  switch (style.centerMode) {
    case _QrCenterMode.none:
      break;
    case _QrCenterMode.avatar:
      _paintQrCenterAvatar(
        canvas,
        center: center,
        palette: palette,
        avatarImage: avatarImage,
        fallbackText: fallbackText,
        size: size,
      );
      break;
    case _QrCenterMode.logo:
      _paintQrCenterLogo(canvas, center: center, palette: palette, size: size);
      break;
  }
}

void _paintQrCard(
  Canvas canvas, {
  required QrPainter painter,
  required String link,
  required String title,
  required String subtitle,
  required ui.Image? avatarImage,
  required _QrCardStyle style,
  required Size cardSize,
}) {
  final palette = _qrPaletteFor(style.theme);
  final backgroundPaint = Paint()..color = palette.background;
  canvas.drawRect(
    Rect.fromLTWH(0, 0, cardSize.width, cardSize.height),
    backgroundPaint,
  );
  final outer = Rect.fromLTWH(
    96,
    118,
    cardSize.width - 192,
    cardSize.height - 236,
  );
  final cardRect = RRect.fromRectAndRadius(outer, const Radius.circular(56));
  canvas.drawRRect(cardRect, Paint()..color = palette.card);
  canvas.drawRRect(
    cardRect,
    Paint()
      ..color = palette.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2,
  );

  if (style.theme == _QrCardTheme.plainQr) {
    _paintPlainQrCard(
      canvas,
      painter: painter,
      cardSize: cardSize,
      palette: palette,
      avatarImage: avatarImage,
      title: title,
      style: style,
    );
    return;
  }

  if (style.theme == _QrCardTheme.horizontalCard) {
    _paintHorizontalQrCard(
      canvas,
      painter: painter,
      cardSize: cardSize,
      palette: palette,
      avatarImage: avatarImage,
      title: title,
      subtitle: subtitle,
      style: style,
      link: link,
    );
    return;
  }

  var cursorY = 200.0;
  if (style.showAvatar) {
    _paintQrAvatar(
      canvas,
      center: Offset(cardSize.width / 2, cursorY + 72),
      radius: 72,
      palette: palette,
      avatarImage: avatarImage,
      fallbackText: title,
    );
    cursorY += 174;
  }
  if (style.showTitle && title.trim().isNotEmpty) {
    cursorY += _paintCenteredParagraph(
      canvas,
      title.trim(),
      Offset(cardSize.width / 2, cursorY),
      maxWidth: 760,
      style: TextStyle(
        color: palette.onCard,
        fontSize: 50,
        fontWeight: FontWeight.w800,
        height: 1.15,
      ),
      maxLines: 2,
    );
    cursorY += 16;
    if (subtitle.trim().isNotEmpty) {
      cursorY += _paintCenteredParagraph(
        canvas,
        subtitle.trim(),
        Offset(cardSize.width / 2, cursorY),
        maxWidth: 720,
        style: TextStyle(
          color: palette.muted,
          fontSize: 28,
          fontWeight: FontWeight.w500,
          height: 1.2,
        ),
        maxLines: 1,
      );
    }
    cursorY += 32;
  }

  final qrTop = math.max(610.0, cursorY + 34);
  final qrOuterRect = RRect.fromRectAndRadius(
    Rect.fromLTWH((cardSize.width - 760) / 2, qrTop, 760, 760),
    const Radius.circular(42),
  );
  canvas.drawRRect(qrOuterRect, Paint()..color = palette.qrBackground);
  canvas.drawRRect(
    qrOuterRect,
    Paint()
      ..color = palette.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2,
  );
  final qrRect = Rect.fromLTWH(
    qrOuterRect.outerRect.left + 54,
    qrOuterRect.outerRect.top + 54,
    652,
    652,
  );
  canvas.save();
  canvas.translate(qrRect.left, qrRect.top);
  painter.paint(canvas, qrRect.size);
  canvas.restore();

  switch (style.centerMode) {
    case _QrCenterMode.none:
      break;
    case _QrCenterMode.avatar:
      _paintQrCenterAvatar(
        canvas,
        center: qrRect.center,
        palette: palette,
        avatarImage: avatarImage,
        fallbackText: title,
        size: 112,
      );
      break;
    case _QrCenterMode.logo:
      _paintQrCenterLogo(
        canvas,
        center: qrRect.center,
        palette: palette,
        size: 112,
      );
      break;
  }

  final linkTop = qrOuterRect.outerRect.bottom + 42;
  _paintCenteredParagraph(
    canvas,
    link,
    Offset(cardSize.width / 2, linkTop),
    maxWidth: 780,
    style: TextStyle(
      color: palette.muted,
      fontSize: 24,
      fontWeight: FontWeight.w500,
      height: 1.25,
    ),
    maxLines: 2,
  );
}

Future<ui.Image?> _loadQrAvatarImage(String url) async {
  final trimmed = url.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  try {
    final response = await http.get(Uri.parse(trimmed));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }
    final codec = await ui.instantiateImageCodec(response.bodyBytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  } catch (_) {
    return null;
  }
}

void _paintQrAvatar(
  Canvas canvas, {
  required Offset center,
  required double radius,
  required _QrCardPalette palette,
  required ui.Image? avatarImage,
  required String fallbackText,
}) {
  canvas.drawCircle(
    center,
    radius + 6,
    Paint()..color = palette.primary.withValues(alpha: 0.16),
  );
  canvas.drawCircle(center, radius, Paint()..color = palette.qrBackground);
  if (avatarImage != null) {
    final rect = Rect.fromCircle(center: center, radius: radius - 4);
    canvas.save();
    canvas.clipPath(Path()..addOval(rect));
    paintImage(
      canvas: canvas,
      rect: rect,
      image: avatarImage,
      fit: BoxFit.cover,
    );
    canvas.restore();
    return;
  }
  final initial = _qrInitial(fallbackText);
  _paintCenteredParagraph(
    canvas,
    initial,
    Offset(center.dx, center.dy - 22),
    maxWidth: radius * 1.5,
    style: TextStyle(
      color: palette.primary,
      fontSize: 54,
      fontWeight: FontWeight.w900,
      height: 1,
    ),
    maxLines: 1,
  );
}

void _paintQrCenterAvatar(
  Canvas canvas, {
  required Offset center,
  required _QrCardPalette palette,
  required ui.Image? avatarImage,
  required String fallbackText,
  double size = 132,
}) {
  final rect = Rect.fromCenter(center: center, width: size, height: size);
  final pad = math.max(8.0, size * 0.075);
  final outerRadius = math.max(24.0, size * 0.24);
  final innerRadius = math.max(20.0, size * 0.19);
  final outer = RRect.fromRectAndRadius(
    rect.inflate(pad),
    Radius.circular(outerRadius),
  );
  canvas.drawRRect(outer, Paint()..color = palette.qrBackground);
  canvas.drawRRect(
    outer,
    Paint()
      ..color = palette.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2,
  );
  if (avatarImage != null) {
    final imageRect = rect;
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(imageRect, Radius.circular(innerRadius)),
    );
    paintImage(
      canvas: canvas,
      rect: imageRect,
      image: avatarImage,
      fit: BoxFit.cover,
    );
    canvas.restore();
    return;
  }
  canvas.drawRRect(
    RRect.fromRectAndRadius(rect, Radius.circular(innerRadius)),
    Paint()..color = palette.primary,
  );
  _paintCenteredParagraph(
    canvas,
    _qrInitial(fallbackText),
    Offset(center.dx, center.dy - size * 0.115),
    maxWidth: size * 0.78,
    style: TextStyle(
      color: Colors.white,
      fontSize: size * 0.30,
      fontWeight: FontWeight.w900,
      height: 1,
    ),
    maxLines: 1,
  );
}

void _paintQrCenterLogo(
  Canvas canvas, {
  required Offset center,
  required _QrCardPalette palette,
  double size = 132,
}) {
  final rect = Rect.fromCenter(center: center, width: size, height: size);
  final pad = math.max(8.0, size * 0.075);
  final outerRadius = math.max(24.0, size * 0.24);
  final innerRadius = math.max(20.0, size * 0.19);
  final outer = RRect.fromRectAndRadius(
    rect.inflate(pad),
    Radius.circular(outerRadius),
  );
  canvas.drawRRect(outer, Paint()..color = palette.qrBackground);
  canvas.drawRRect(
    RRect.fromRectAndRadius(rect, Radius.circular(innerRadius)),
    Paint()..color = palette.primary,
  );
  _paintCenteredParagraph(
    canvas,
    'CsAC',
    Offset(center.dx, center.dy - size * 0.10),
    maxWidth: size * 0.82,
    style: TextStyle(
      color: Colors.white,
      fontSize: size * 0.22,
      fontWeight: FontWeight.w900,
      height: 1,
    ),
    maxLines: 1,
  );
}

double _paintCenteredParagraph(
  Canvas canvas,
  String text,
  Offset topCenter, {
  required double maxWidth,
  required TextStyle style,
  required int maxLines,
}) {
  final paragraphStyle = ui.ParagraphStyle(
    textAlign: TextAlign.center,
    maxLines: maxLines,
    ellipsis: maxLines == 1 ? '...' : null,
    fontSize: style.fontSize,
    fontWeight: style.fontWeight,
    height: style.height,
  );
  final builder = ui.ParagraphBuilder(paragraphStyle)
    ..pushStyle(style.getTextStyle())
    ..addText(text);
  final paragraph = builder.build()
    ..layout(ui.ParagraphConstraints(width: maxWidth));
  canvas.drawParagraph(
    paragraph,
    Offset(topCenter.dx - maxWidth / 2, topCenter.dy),
  );
  return paragraph.height;
}

double _paintLeftParagraph(
  Canvas canvas,
  String text,
  Offset topLeft, {
  required double maxWidth,
  required TextStyle style,
  required int maxLines,
}) {
  final paragraphStyle = ui.ParagraphStyle(
    textAlign: TextAlign.left,
    maxLines: maxLines,
    ellipsis: maxLines == 1 ? '...' : null,
    fontSize: style.fontSize,
    fontWeight: style.fontWeight,
    height: style.height,
  );
  final builder = ui.ParagraphBuilder(paragraphStyle)
    ..pushStyle(style.getTextStyle())
    ..addText(text);
  final paragraph = builder.build()
    ..layout(ui.ParagraphConstraints(width: maxWidth));
  canvas.drawParagraph(paragraph, topLeft);
  return paragraph.height;
}

String _qrInitial(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return 'C';
  }
  final first = trimmed.runes.first;
  return String.fromCharCode(first).toUpperCase();
}

ImageProvider<Object>? _qrCenterImageProvider(
  _QrCardStyle style,
  String avatarUrl,
) {
  if (style.centerMode != _QrCenterMode.avatar || avatarUrl.trim().isEmpty) {
    return null;
  }
  return NetworkImage(avatarUrl.trim());
}

class _QrCardPreview extends StatelessWidget {
  const _QrCardPreview({
    required this.link,
    required this.title,
    required this.subtitle,
    required this.avatarUrl,
    required this.fallbackIcon,
    required this.semanticsLabel,
    required this.style,
    this.helperText = '',
  });

  final String link;
  final String title;
  final String subtitle;
  final String avatarUrl;
  final IconData fallbackIcon;
  final String semanticsLabel;
  final _QrCardStyle style;
  final String helperText;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = _qrPaletteFor(style.theme);
    final centerImage = _qrCenterImageProvider(style, avatarUrl);
    final plain = style.theme == _QrCardTheme.plainQr;
    final horizontal = style.theme == _QrCardTheme.horizontalCard;
    final previewCenterSize = horizontal ? 30.0 : 38.0;
    final qrBlock = DecoratedBox(
      decoration: BoxDecoration(
        color: palette.qrBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox.square(
          dimension: horizontal ? 190 : 220,
          child: Stack(
            alignment: Alignment.center,
            children: [
              QrImageView(
                data: link,
                version: QrVersions.auto,
                errorCorrectionLevel: QrErrorCorrectLevel.M,
                size: horizontal ? 190 : 220,
                backgroundColor: palette.qrBackground,
                eyeStyle: QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: palette.qrForeground,
                ),
                dataModuleStyle: QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: palette.qrForeground,
                ),
                embeddedImage: style.centerMode == _QrCenterMode.logo
                    ? null
                    : centerImage,
                embeddedImageStyle: centerImage == null
                    ? null
                    : QrEmbeddedImageStyle(
                        size: Size.square(previewCenterSize),
                      ),
                semanticsLabel: semanticsLabel,
              ),
              if (style.centerMode == _QrCenterMode.logo)
                _QrLogoCenterMark(palette: palette, size: previewCenterSize),
            ],
          ),
        ),
      ),
    );
    final details = Column(
      crossAxisAlignment: horizontal
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        if (style.showAvatar && !plain) ...[
          _Avatar(url: avatarUrl, fallback: fallbackIcon, radius: 34),
          const SizedBox(height: 12),
        ],
        if (style.showTitle && !plain) ...[
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: palette.onCard,
              fontWeight: FontWeight.w800,
            ),
            textAlign: horizontal ? TextAlign.start : TextAlign.center,
          ),
          if (subtitle.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: palette.muted,
                fontWeight: FontWeight.w500,
              ),
              textAlign: horizontal ? TextAlign.start : TextAlign.center,
            ),
          ],
          if (helperText.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              helperText,
              textAlign: horizontal ? TextAlign.start : TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.muted),
            ),
          ],
          const SizedBox(height: 18),
        ],
        if (horizontal)
          SelectableText(
            link,
            textAlign: horizontal ? TextAlign.start : TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: palette.muted,
              fontFamily: 'monospace',
            ),
          ),
      ],
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: plain
            ? Center(child: qrBlock)
            : horizontal
            ? Row(
                children: [
                  Expanded(child: details),
                  const SizedBox(width: 18),
                  qrBlock,
                ],
              )
            : Column(
                children: [
                  details,
                  qrBlock,
                  const SizedBox(height: 16),
                  SelectableText(
                    link,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: palette.muted,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _QrLogoCenterMark extends StatelessWidget {
  const _QrLogoCenterMark({required this.palette, required this.size});

  final _QrCardPalette palette;
  final double size;

  @override
  Widget build(BuildContext context) {
    final outerRadius = math.max(8.0, size * 0.28);
    final innerRadius = math.max(6.0, size * 0.2);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.qrBackground,
        borderRadius: BorderRadius.circular(outerRadius),
        border: Border.all(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.primary,
            borderRadius: BorderRadius.circular(innerRadius),
          ),
          child: SizedBox(
            width: size,
            height: size,
            child: Center(
              child: Text(
                'CsAC',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: size * 0.26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QrStyleControls extends StatelessWidget {
  const _QrStyleControls({required this.style, required this.onChanged});

  final _QrCardStyle style;
  final ValueChanged<_QrCardStyle> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final plain = style.theme == _QrCardTheme.plainQr;
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              strings.text('QR card style'),
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<_QrCardTheme>(
              initialValue: style.theme,
              decoration: InputDecoration(
                labelText: strings.text('Template'),
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final theme in _QrCardTheme.values)
                  DropdownMenuItem<_QrCardTheme>(
                    value: theme,
                    child: Row(
                      children: [
                        Icon(_qrThemeIcon(theme), size: 20),
                        const SizedBox(width: 10),
                        Text(_qrThemeLabel(strings, theme)),
                      ],
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                onChanged(style.copyWith(theme: value));
              },
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.account_circle_outlined),
              title: Text(strings.text('Show avatar')),
              value: style.showAvatar,
              onChanged: plain
                  ? null
                  : (value) => onChanged(style.copyWith(showAvatar: value)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.badge_outlined),
              title: Text(strings.text('Show name')),
              value: style.showTitle,
              onChanged: plain
                  ? null
                  : (value) => onChanged(style.copyWith(showTitle: value)),
            ),
            const SizedBox(height: 4),
            Text(
              strings.text('Center mark'),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            SegmentedButton<_QrCenterMode>(
              segments: [
                for (final mode in _QrCenterMode.values)
                  ButtonSegment<_QrCenterMode>(
                    value: mode,
                    icon: Icon(_qrCenterModeIcon(mode)),
                    label: Text(_qrCenterModeLabel(strings, mode)),
                  ),
              ],
              selected: {style.centerMode},
              onSelectionChanged: (value) =>
                  onChanged(style.copyWith(centerMode: value.first)),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _qrCenterModeIcon(_QrCenterMode mode) {
  switch (mode) {
    case _QrCenterMode.none:
      return Icons.block;
    case _QrCenterMode.avatar:
      return Icons.account_circle_outlined;
    case _QrCenterMode.logo:
      return Icons.auto_awesome_motion_outlined;
  }
}

String? firstQrBarcodeValue(BarcodeCapture? capture) {
  if (capture == null) {
    return null;
  }
  for (final barcode in capture.barcodes) {
    final value = (barcode.rawValue ?? barcode.displayValue ?? '').trim();
    if (value.isNotEmpty) {
      return value;
    }
  }
  return null;
}

Future<String?> firstQrValueInImagePath(
  String path, {
  MobileScannerController? scanner,
}) async {
  final ownsScanner = scanner == null;
  final activeScanner =
      scanner ??
      MobileScannerController(
        autoStart: false,
        formats: const [BarcodeFormat.qrCode],
      );
  try {
    final capture = await activeScanner.analyzeImage(
      path,
      formats: const [BarcodeFormat.qrCode],
    );
    return firstQrBarcodeValue(capture);
  } finally {
    if (ownsScanner) {
      unawaited(activeScanner.dispose());
    }
  }
}

Future<String> cacheQrScanImageUrl(String url) async {
  final response = await http.get(Uri.parse(url));
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception('HTTP ${response.statusCode}');
  }
  return writeTemporaryQrScanImage(
    response.bodyBytes,
    Uri.tryParse(url)?.path ?? 'image.png',
  );
}

class UserQrScreen extends StatefulWidget {
  const UserQrScreen({super.key, required this.state});

  final CsacAppState state;

  @override
  State<UserQrScreen> createState() => _UserQrScreenState();
}

class _UserQrScreenState extends State<UserQrScreen> {
  bool sharing = false;
  _QrCardStyle qrStyle = const _QrCardStyle();

  CsacUser? get user => widget.state.user;

  String get profileLink {
    final uid = user?.uid ?? 0;
    return uid <= 0 ? '' : csacUserProfileDeepLink(uid);
  }

  Future<void> copyLink() async {
    final link = profileLink;
    if (link.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: link));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.text('Profile link copied.'))),
      );
    }
  }

  Future<void> shareQr() async {
    final link = profileLink;
    final current = user;
    if (link.isEmpty || current == null || sharing) {
      return;
    }
    setState(() => sharing = true);
    final strings = context.strings;
    try {
      await _shareCsacQrPng(
        context,
        link: link,
        title: strings.text('Share my user QR code'),
        subject: strings.text('CsAC user QR code'),
        fileName: 'csac-user-${current.uid}.png',
        cardTitle: current.nickname,
        cardSubtitle: 'UID ${current.uid}',
        avatarUrl: widget.state.currentUserAvatar,
        style: qrStyle,
      );
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              friendlyMobileFileError(
                context.strings,
                err,
                fallbackKey: 'Share failed: {error}',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => sharing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final current = user;
    final link = profileLink;
    return Scaffold(
      appBar: AppBar(title: Text(strings.text('My QR code'))),
      body: SafeArea(
        child: current == null || link.isEmpty
            ? _EmptyPanel(message: strings.text('Not logged in'))
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _QrCardPreview(
                    link: link,
                    title: current.nickname,
                    subtitle: 'UID ${current.uid}',
                    avatarUrl: widget.state.currentUserAvatar,
                    fallbackIcon: Icons.person_rounded,
                    semanticsLabel: strings.text(
                      'My CsAC user profile QR code',
                    ),
                    style: qrStyle,
                  ),
                  const SizedBox(height: 12),
                  _QrStyleControls(
                    style: qrStyle,
                    onChanged: (style) => setState(() => qrStyle = style),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: sharing ? null : shareQr,
                    icon: sharing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.ios_share_outlined),
                    label: Text(strings.text('Share QR code')),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: copyLink,
                    icon: const Icon(Icons.link),
                    label: Text(strings.text('Copy profile link')),
                  ),
                ],
              ),
      ),
    );
  }
}

class GroupQrScreen extends StatefulWidget {
  const GroupQrScreen({super.key, required this.group});

  final GroupProfile group;

  @override
  State<GroupQrScreen> createState() => _GroupQrScreenState();
}

class _GroupQrScreenState extends State<GroupQrScreen> {
  bool sharing = false;
  _QrCardStyle qrStyle = const _QrCardStyle();

  String get groupLink => csacGroupChatDeepLink(widget.group.id);

  Future<void> copyLink() async {
    final link = groupLink;
    await Clipboard.setData(ClipboardData(text: link));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.text('Group link copied.'))),
      );
    }
  }

  Future<void> shareQr() async {
    final group = widget.group;
    if (sharing) {
      return;
    }
    setState(() => sharing = true);
    final strings = context.strings;
    try {
      await _shareCsacQrPng(
        context,
        link: groupLink,
        title: strings.text('Share group QR code'),
        subject: strings.text('CsAC group QR code'),
        fileName: 'csac-group-${group.id}.png',
        cardTitle: group.name,
        cardSubtitle: strings.format('Room {id}', {'id': group.id}),
        avatarUrl: group.avatar,
        style: qrStyle,
      );
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              friendlyMobileFileError(
                context.strings,
                err,
                fallbackKey: 'Share failed: {error}',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => sharing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final group = widget.group;
    final link = groupLink;
    return Scaffold(
      appBar: AppBar(title: Text(strings.text('Group QR code'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _QrCardPreview(
              link: link,
              title: group.name,
              subtitle: strings.format('Room {id}', {'id': group.id}),
              avatarUrl: group.avatar,
              fallbackIcon: Icons.groups_rounded,
              helperText: strings.text('Scan to open this group chat in CsAC.'),
              semanticsLabel: strings.text('CsAC group QR code'),
              style: qrStyle,
            ),
            const SizedBox(height: 12),
            _QrStyleControls(
              style: qrStyle,
              onChanged: (style) => setState(() => qrStyle = style),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: sharing ? null : shareQr,
              icon: sharing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.ios_share_outlined),
              label: Text(strings.text('Share QR code')),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: copyLink,
              icon: const Icon(Icons.link),
              label: Text(strings.text('Copy group link')),
            ),
          ],
        ),
      ),
    );
  }
}

class CsacQrShareScreen extends StatefulWidget {
  const CsacQrShareScreen({
    super.key,
    required this.appBarTitle,
    required this.link,
    required this.cardTitle,
    this.cardSubtitle = '',
    this.avatarUrl = '',
    required this.fallbackIcon,
    required this.helperText,
    required this.semanticsLabel,
    required this.shareTitle,
    required this.shareSubject,
    required this.fileName,
    required this.copySnackText,
  });

  final String appBarTitle;
  final String link;
  final String cardTitle;
  final String cardSubtitle;
  final String avatarUrl;
  final IconData fallbackIcon;
  final String helperText;
  final String semanticsLabel;
  final String shareTitle;
  final String shareSubject;
  final String fileName;
  final String copySnackText;

  @override
  State<CsacQrShareScreen> createState() => _CsacQrShareScreenState();
}

class _CsacQrShareScreenState extends State<CsacQrShareScreen> {
  bool sharing = false;
  _QrCardStyle qrStyle = const _QrCardStyle();

  Future<void> copyLink() async {
    await Clipboard.setData(ClipboardData(text: widget.link));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(widget.copySnackText)));
    }
  }

  Future<void> shareQr() async {
    if (sharing) {
      return;
    }
    setState(() => sharing = true);
    try {
      await _shareCsacQrPng(
        context,
        link: widget.link,
        title: widget.shareTitle,
        subject: widget.shareSubject,
        fileName: widget.fileName,
        cardTitle: widget.cardTitle,
        cardSubtitle: widget.cardSubtitle,
        avatarUrl: widget.avatarUrl,
        style: qrStyle,
      );
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              friendlyMobileFileError(
                context.strings,
                err,
                fallbackKey: 'Share failed: {error}',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => sharing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Scaffold(
      appBar: AppBar(title: Text(widget.appBarTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _QrCardPreview(
              link: widget.link,
              title: widget.cardTitle,
              subtitle: widget.cardSubtitle,
              avatarUrl: widget.avatarUrl,
              fallbackIcon: widget.fallbackIcon,
              helperText: widget.helperText,
              semanticsLabel: widget.semanticsLabel,
              style: qrStyle,
            ),
            const SizedBox(height: 12),
            _QrStyleControls(
              style: qrStyle,
              onChanged: (style) => setState(() => qrStyle = style),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: sharing ? null : shareQr,
              icon: sharing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.ios_share_outlined),
              label: Text(strings.text('Share QR code')),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: copyLink,
              icon: const Icon(Icons.link),
              label: Text(strings.text('Copy link')),
            ),
          ],
        ),
      ),
    );
  }
}

Future<Uri?> confirmScannedCsacUri(BuildContext context, Uri uri) {
  return Navigator.of(context).push<Uri>(
    MaterialPageRoute<Uri>(builder: (_) => CsacQrScanResultScreen(uri: uri)),
  );
}

class CsacQrScanResultScreen extends StatelessWidget {
  const CsacQrScanResultScreen({super.key, required this.uri});

  final Uri uri;

  Future<void> confirm(BuildContext context) async {
    await QrScanHistoryStore.add(uri.toString());
    if (context.mounted) {
      Navigator.of(context).pop(uri);
    }
  }

  Future<void> copyLink(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: uri.toString()));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.text('Link copied.'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final target = parseCsacDeepLink(uri);
    if (!target.isSupported) {
      return Scaffold(
        appBar: AppBar(title: Text(strings.text('Scan result'))),
        body: _EmptyPanel(message: strings.text('Unsupported CsAC link.')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(strings.text('Scan result'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      child: Icon(_deepLinkTargetIcon(target.action)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _deepLinkTargetLabel(strings, target),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            strings.text(
                              'Confirm before opening this scanned link.',
                            ),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.category_outlined),
                    title: Text(strings.text('Link type')),
                    subtitle: Text(_deepLinkTargetLabel(strings, target)),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.tag),
                    title: Text(strings.text('Identifier')),
                    subtitle: Text(_deepLinkTargetIdentifier(strings, target)),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.link),
                    title: Text(strings.text('Link')),
                    subtitle: SelectableText(uri.toString()),
                    trailing: IconButton(
                      tooltip: strings.text('Copy'),
                      onPressed: () => copyLink(context),
                      icon: const Icon(Icons.copy),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => confirm(context),
              icon: const Icon(Icons.open_in_new),
              label: Text(strings.text('Open')),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(strings.text('Cancel')),
            ),
          ],
        ),
      ),
    );
  }
}

class QrScanHistoryScreen extends StatefulWidget {
  const QrScanHistoryScreen({super.key});

  @override
  State<QrScanHistoryScreen> createState() => _QrScanHistoryScreenState();
}

class _QrScanHistoryScreenState extends State<QrScanHistoryScreen> {
  List<QrScanHistoryEntry> entries = const <QrScanHistoryEntry>[];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    final loaded = await QrScanHistoryStore.loadAll();
    if (mounted) {
      setState(() {
        entries = loaded;
        loading = false;
      });
    }
  }

  Future<void> clearHistory() async {
    await QrScanHistoryStore.clear();
    if (!mounted) {
      return;
    }
    setState(() => entries = const <QrScanHistoryEntry>[]);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.strings.text('Scan history cleared.'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.text('Scan history')),
        actions: [
          IconButton(
            tooltip: strings.text('Clear history'),
            onPressed: entries.isEmpty ? null : clearHistory,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : entries.isEmpty
            ? _EmptyPanel(message: strings.text('No scan history.'))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  final uri = Uri.tryParse(entry.link);
                  final target = uri == null
                      ? const CsacDeepLinkTarget(CsacDeepLinkAction.unsupported)
                      : parseCsacDeepLink(uri);
                  return Card(
                    elevation: 0,
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Icon(_deepLinkTargetIcon(target.action)),
                      ),
                      title: Text(_deepLinkTargetLabel(strings, target)),
                      subtitle: Text(
                        [
                          _deepLinkTargetIdentifier(strings, target),
                          _formatScanHistoryTime(entry.scannedAt),
                        ].where((value) => value.trim().isNotEmpty).join(' | '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: uri == null || !target.isSupported
                          ? null
                          : () => Navigator.of(context).pop(uri),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

String _deepLinkTargetLabel(CsacStrings strings, CsacDeepLinkTarget target) {
  switch (target.action) {
    case CsacDeepLinkAction.chats:
      return strings.text('Chat list');
    case CsacDeepLinkAction.space:
      return strings.text('Space');
    case CsacDeepLinkAction.spacePost:
      return strings.text('Space post');
    case CsacDeepLinkAction.search:
      return strings.text('Search');
    case CsacDeepLinkAction.searchResult:
      return strings.text('Search result');
    case CsacDeepLinkAction.notices:
      return strings.text('Notices');
    case CsacDeepLinkAction.emApps:
      return strings.text('eMApps');
    case CsacDeepLinkAction.emApp:
      return strings.text('eMApp');
    case CsacDeepLinkAction.profile:
      return strings.text('Profile');
    case CsacDeepLinkAction.userProfile:
      return strings.text('User profile');
    case CsacDeepLinkAction.groupChat:
      return strings.text('Group chat');
    case CsacDeepLinkAction.privateChat:
      return strings.text('Private chat');
    case CsacDeepLinkAction.groupMessage:
    case CsacDeepLinkAction.privateMessage:
      return strings.text('Message');
    case CsacDeepLinkAction.unsupported:
      return strings.text('Unsupported link');
  }
}

String _deepLinkTargetIdentifier(
  CsacStrings strings,
  CsacDeepLinkTarget target,
) {
  switch (target.action) {
    case CsacDeepLinkAction.searchResult:
      return target.query ?? '';
    case CsacDeepLinkAction.emApp:
      return target.appId ?? '';
    case CsacDeepLinkAction.groupMessage:
    case CsacDeepLinkAction.privateMessage:
      return strings.format('Conversation {id} | Message {messageId}', {
        'id': target.id ?? 0,
        'messageId': target.messageId ?? 0,
      });
    case CsacDeepLinkAction.chats:
    case CsacDeepLinkAction.space:
    case CsacDeepLinkAction.search:
    case CsacDeepLinkAction.notices:
    case CsacDeepLinkAction.emApps:
    case CsacDeepLinkAction.profile:
      return strings.text('No ID');
    case CsacDeepLinkAction.spacePost:
    case CsacDeepLinkAction.userProfile:
    case CsacDeepLinkAction.groupChat:
    case CsacDeepLinkAction.privateChat:
      return '${target.id ?? 0}';
    case CsacDeepLinkAction.unsupported:
      return '';
  }
}

IconData _deepLinkTargetIcon(CsacDeepLinkAction action) {
  switch (action) {
    case CsacDeepLinkAction.chats:
      return Icons.chat_bubble_outline;
    case CsacDeepLinkAction.space:
    case CsacDeepLinkAction.spacePost:
      return Icons.public_outlined;
    case CsacDeepLinkAction.search:
    case CsacDeepLinkAction.searchResult:
      return Icons.manage_search_outlined;
    case CsacDeepLinkAction.notices:
      return Icons.notifications_none;
    case CsacDeepLinkAction.emApps:
    case CsacDeepLinkAction.emApp:
      return Icons.apps_outlined;
    case CsacDeepLinkAction.profile:
    case CsacDeepLinkAction.userProfile:
      return Icons.person_outline;
    case CsacDeepLinkAction.groupChat:
      return Icons.groups_outlined;
    case CsacDeepLinkAction.privateChat:
      return Icons.person_add_alt_outlined;
    case CsacDeepLinkAction.groupMessage:
    case CsacDeepLinkAction.privateMessage:
      return Icons.mark_chat_unread_outlined;
    case CsacDeepLinkAction.unsupported:
      return Icons.link_off_outlined;
  }
}

String _formatScanHistoryTime(int millis) {
  if (millis <= 0) {
    return '';
  }
  return DateTime.fromMillisecondsSinceEpoch(
    millis,
  ).toLocal().toString().split('.').first;
}

class CsacQrScannerScreen extends StatefulWidget {
  const CsacQrScannerScreen({super.key});

  @override
  State<CsacQrScannerScreen> createState() => _CsacQrScannerScreenState();
}

class _CsacQrScannerScreenState extends State<CsacQrScannerScreen> {
  late final MobileScannerController controller;
  bool handling = false;
  bool pickingImage = false;

  @override
  void initState() {
    super.initState();
    controller = MobileScannerController(
      formats: const [BarcodeFormat.qrCode],
      detectionSpeed: DetectionSpeed.noDuplicates,
    );
  }

  @override
  void dispose() {
    unawaited(controller.dispose());
    super.dispose();
  }

  void showInvalidQrSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.strings.text('This is not a CsAC QR code.')),
      ),
    );
  }

  Future<bool> handleScannedValue(
    String value, {
    bool showInvalid = true,
  }) async {
    final uri = Uri.tryParse(value);
    if (uri == null || !isCsacDeepLink(uri)) {
      if (showInvalid) {
        showInvalidQrSnack();
      }
      return false;
    }
    final target = parseCsacDeepLink(uri);
    if (!target.isSupported) {
      if (showInvalid) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.strings.text('Unsupported CsAC link.')),
          ),
        );
      }
      return false;
    }
    final confirmed = await confirmScannedCsacUri(context, uri);
    if (!mounted || confirmed == null) {
      return false;
    }
    Navigator.of(context).pop(confirmed);
    return true;
  }

  void handleDetect(BarcodeCapture capture) {
    if (handling) {
      return;
    }
    final value = firstQrBarcodeValue(capture);
    if (value == null) {
      return;
    }
    setState(() => handling = true);
    unawaited(controller.stop());
    unawaited(() async {
      final completed = await handleScannedValue(value, showInvalid: false);
      if (!completed && mounted) {
        setState(() => handling = false);
        unawaited(controller.start());
      }
    }());
  }

  Future<void> pickImageQr() async {
    if (pickingImage || handling) {
      return;
    }
    setState(() => pickingImage = true);
    var stoppedCamera = false;
    var completed = false;
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null) {
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() => handling = true);
      await controller.stop();
      stoppedCamera = true;
      final value = await firstQrValueInImagePath(
        picked.path,
        scanner: controller,
      );
      if (!mounted) {
        return;
      }
      if (value == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.strings.text('No QR code found in this image.'),
            ),
          ),
        );
        return;
      }
      completed = await handleScannedValue(value);
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.strings.format('QR scan failed: {error}', {'error': err}),
            ),
          ),
        );
      }
    } finally {
      if (mounted && !completed) {
        setState(() {
          pickingImage = false;
          handling = false;
        });
        if (stoppedCamera) {
          unawaited(controller.start());
        }
      }
    }
  }

  Future<void> openHistory() async {
    if (handling) {
      return;
    }
    final uri = await Navigator.of(context).push<Uri>(
      MaterialPageRoute<Uri>(builder: (_) => const QrScanHistoryScreen()),
    );
    if (!mounted || uri == null) {
      return;
    }
    Navigator.of(context).pop(uri);
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colors = Theme.of(context).colorScheme;
    if (!isMobilePlatform) {
      return Scaffold(
        appBar: AppBar(title: Text(strings.text('Scan QR code'))),
        body: _EmptyPanel(
          message: strings.text('QR scanning is only available on mobile.'),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.text('Scan QR code')),
        actions: [
          IconButton(
            tooltip: strings.text('Scan history'),
            onPressed: handling ? null : openHistory,
            icon: const Icon(Icons.history),
          ),
          IconButton(
            tooltip: strings.text('Choose from album'),
            onPressed: pickingImage || handling ? null : pickImageQr,
            icon: pickingImage
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.photo_library_outlined),
          ),
        ],
      ),
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(controller: controller, onDetect: handleDetect),
          Center(
            child: IgnorePointer(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 3),
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              color: Colors.black.withValues(alpha: 0.62),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.qr_code_scanner, color: colors.primaryContainer),
                  const SizedBox(height: 8),
                  Text(
                    strings.text(
                      'Scan a CsAC user or group QR code or link QR code',
                    ),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    strings.text('Only CsAC URL scheme links will be opened.'),
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
          if (handling)
            const Center(
              child: SizedBox(
                width: 42,
                height: 42,
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }
}

Future<Uri?> openCsacQrScanner(BuildContext context) {
  return Navigator.of(context).push<Uri>(
    MaterialPageRoute<Uri>(builder: (_) => const CsacQrScannerScreen()),
  );
}
