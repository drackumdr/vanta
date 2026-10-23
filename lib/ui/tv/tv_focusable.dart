import 'package:flutter/material.dart';

/// Contenedor de foco de alto contraste optimizado para Android TV y navegación D-Pad.
class TvFocusable extends StatefulWidget {
  const TvFocusable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.autofocus = false,
    this.focusNode,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.focusBorderColor = const Color(0xFF00E5FF),
    this.focusBorderWidth = 2.5,
    this.scaleOnFocus = 1.04,
    this.padding,
    this.backgroundColor,
    this.focusedBackgroundColor,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool autofocus;
  final FocusNode? focusNode;
  final BorderRadius borderRadius;
  final Color focusBorderColor;
  final double focusBorderWidth;
  final double scaleOnFocus;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final Color? focusedBackgroundColor;

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      enabled: widget.onTap != null || widget.onLongPress != null,
      onShowFocusHighlight: (v) => setState(() => _isFocused = v),
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap?.call();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: _isFocused ? widget.scaleOnFocus : 1.0,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            padding: widget.padding,
            decoration: BoxDecoration(
              color: _isFocused
                  ? (widget.focusedBackgroundColor ?? widget.backgroundColor)
                  : widget.backgroundColor,
              borderRadius: widget.borderRadius,
              border: Border.all(
                color: _isFocused ? widget.focusBorderColor : Colors.transparent,
                width: widget.focusBorderWidth,
              ),
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: widget.focusBorderColor.withValues(alpha: 0.35),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
