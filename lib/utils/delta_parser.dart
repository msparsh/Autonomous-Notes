import 'dart:convert';
import 'package:flutter/material.dart';

TextSpan parseDeltaToTextSpan(String content, TextStyle baseStyle) {
  if (content.isEmpty) return const TextSpan();
  if (!content.startsWith('[')) {
    return TextSpan(text: content, style: baseStyle);
  }

  try {
    final List<dynamic> delta = jsonDecode(content);
    final List<TextSpan> children = [];

    for (final op in delta) {
      if (op is Map && op.containsKey('insert')) {
        final insert = op['insert'];
        if (insert is String) {
          TextStyle style = baseStyle;
          if (op.containsKey('attributes')) {
            final attrs = op['attributes'];
            if (attrs is Map) {
              if (attrs['bold'] == true) style = style.copyWith(fontWeight: FontWeight.bold);
              if (attrs['italic'] == true) style = style.copyWith(fontStyle: FontStyle.italic);
              if (attrs['underline'] == true) style = style.copyWith(decoration: TextDecoration.underline);
              if (attrs['strike'] == true) style = style.copyWith(decoration: TextDecoration.lineThrough);
            }
          }
          children.add(TextSpan(text: insert, style: style));
        }
      }
    }
    return TextSpan(children: children);
  } catch (e) {
    return TextSpan(text: content, style: baseStyle);
  }
}
