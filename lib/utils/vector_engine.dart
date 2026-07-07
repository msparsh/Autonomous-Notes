import 'dart:math' as math;
import 'package:ml_linalg/vector.dart';

class BridgeResult {
  final String title;
  final String content;
  BridgeResult({required this.title, required this.content});
}

class VectorEngine {
  static const int vectorSize = 128;

  // Stop words to clean up text before tokenization
  static const Set<String> stopWords = {
    'i', 'me', 'my', 'myself', 'we', 'our', 'ours', 'ourselves', 'you', 'your', 'yours',
    'he', 'him', 'his', 'she', 'her', 'it', 'its', 'they', 'them', 'their', 'what', 'which',
    'who', 'whom', 'this', 'that', 'these', 'those', 'am', 'is', 'are', 'was', 'were', 'be',
    'been', 'being', 'have', 'has', 'had', 'having', 'do', 'does', 'did', 'doing', 'a', 'an',
    'the', 'and', 'but', 'if', 'or', 'because', 'as', 'until', 'while', 'of', 'at', 'by',
    'for', 'with', 'about', 'against', 'between', 'into', 'through', 'during', 'before',
    'after', 'above', 'below', 'to', 'from', 'up', 'down', 'in', 'out', 'on', 'off', 'over',
    'under', 'again', 'further', 'then', 'once', 'here', 'there', 'when', 'where', 'why',
    'how', 'all', 'any', 'both', 'each', 'few', 'more', 'most', 'other', 'some', 'such',
    'no', 'nor', 'not', 'only', 'own', 'same', 'so', 'than', 'too', 'very', 's', 't', 'can',
    'will', 'just', 'don', 'should', 'now'
  };

  /// Clean text and return list of filtered words
  static List<String> tokenize(String text) {
    final cleaned = text.toLowerCase().replaceAll(RegExp(r'[^\w\s\-]'), ' ');
    return cleaned
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty && !stopWords.contains(word))
        .toList();
  }

  /// Generate a high-dimensional vector for a note using Feature Hashing (hashing trick)
  static List<double> generateEmbedding(String title, String content) {
    final titleWords = tokenize(title);
    final contentWords = tokenize(tokenizeQuillJson(content));
    
    final List<double> rawVector = List.filled(vectorSize, 0.0);
    
    // Feature hashing with weighting (Title is weighted higher, e.g., 3.0)
    for (final word in titleWords) {
      final idx = word.hashCode.abs() % vectorSize;
      rawVector[idx] += 3.0;
    }
    
    for (final word in contentWords) {
      final idx = word.hashCode.abs() % vectorSize;
      rawVector[idx] += 1.0;
    }

    // Normalize the vector
    double sumSq = 0.0;
    for (final val in rawVector) {
      sumSq += val * val;
    }
    
    if (sumSq > 0.0) {
      final double magnitude = math.sqrt(sumSq);
      for (int i = 0; i < rawVector.length; i++) {
        rawVector[i] /= magnitude;
      }
    } else {
      // Fallback
      rawVector[0] = 0.01;
    }

    return rawVector;
  }

  /// Helper to safely extract raw text from Quill delta JSON if applicable
  static String tokenizeQuillJson(String content) {
    if (!content.startsWith('[')) return content;
    try {
      // Simple parse without importing full libraries, or fallback
      final cleanBuffer = StringBuffer();
      int index = 0;
      while (true) {
        index = content.indexOf('"insert":', index);
        if (index == -1) break;
        index += 9;
        // Find the start of the string
        while (index < content.length && (content[index] == ' ' || content[index] == '\t')) {
          index++;
        }
        if (index < content.length && content[index] == '"') {
          index++;
          final start = index;
          while (index < content.length && content[index] != '"') {
            if (content[index] == '\\' && index + 1 < content.length) {
              index += 2;
            } else {
              index++;
            }
          }
          if (index < content.length) {
            cleanBuffer.write(content.substring(start, index));
          }
        }
      }
      return cleanBuffer.toString();
    } catch (_) {
      return content;
    }
  }

  /// Calculate cosine similarity using ml_linalg Vector operations
  static double computeSimilarity(List<double> vecA, List<double> vecB) {
    if (vecA.length != vecB.length || vecA.isEmpty) return 0.0;

    final vectorA = Vector.fromList(vecA);
    final vectorB = Vector.fromList(vecB);

    final normA = vectorA.norm();
    final normB = vectorB.norm();

    if (normA == 0.0 || normB == 0.0) return 0.0;

    final dotProduct = vectorA.dot(vectorB);
    final similarity = dotProduct / (normA * normB);

    return similarity.clamp(-1.0, 1.0);
  }

  // ─── Semantic Interpolation ────────────────────────────────────────────────

  /// Compute the normalized elementwise average (midpoint) of two vectors.
  /// This point in the shared vector space represents the "conceptual midpoint"
  /// between two notes — the latent space region that both concepts share.
  static List<double> interpolateVectors(List<double> vecA, List<double> vecB) {
    if (vecA.length != vecB.length || vecA.isEmpty) return vecA;

    final List<double> midpoint = List.generate(
      vecA.length,
      (i) => (vecA[i] + vecB[i]) / 2.0,
    );

    // Re-normalize the midpoint vector so it lives on the unit hypersphere
    double sumSq = 0.0;
    for (final val in midpoint) {
      sumSq += val * val;
    }
    if (sumSq > 0.0) {
      final double magnitude = math.sqrt(sumSq);
      for (int i = 0; i < midpoint.length; i++) {
        midpoint[i] /= magnitude;
      }
    }

    return midpoint;
  }

  /// Given two notes and the current vocabulary, generate a meaningful bridge
  /// note title and content by finding the conceptual intersection keywords.
  ///
  /// Strategy:
  ///   1. Find keywords unique to each note (its "identity").
  ///   2. Find keywords shared (or near-shared) by both — the "bridge zone".
  ///   3. Construct a title that names the bridge concept.
  ///   4. Construct a content sentence explaining the connection.
  static BridgeResult generateBridgeContent({
    required String titleA,
    required String contentA,
    required String titleB,
    required String contentB,
    required List<double> vecA,
    required List<double> vecB,
    required List<String> vocab,
  }) {
    final tokensA = _extractSignificantWords(titleA, contentA);
    final tokensB = _extractSignificantWords(titleB, contentB);

    final setA = tokensA.toSet();
    final setB = tokensB.toSet();

    // Words that appear in both — the conceptual overlap
    final shared = setA.intersection(setB).toList();

    // Words unique to each side — their distinct identities
    final uniqueA = setA.difference(setB).toList();
    final uniqueB = setB.difference(setA).toList();

    // Also mine the vocabulary via vector midpoint: find top dimensions
    // activated by both vectors and map them back to vocab words.
    final List<_VocabScore> vocabScores = [];
    if (vocab.isNotEmpty && vecA.length == vecB.length) {
      // Use a TF-IDF-flavored hashing trick: for each vocab word, compute
      // its hash dimension and check how active that dimension is in both vecs.
      for (int vi = 0; vi < vocab.length && vi < 500; vi++) {
        final word = vocab[vi];
        final dim = word.hashCode.abs() % vecA.length;
        final combined = (vecA[dim] + vecB[dim]) / 2.0;
        if (combined > 0.01) {
          vocabScores.add(_VocabScore(word, combined));
        }
      }
      vocabScores.sort((a, b) => b.score.compareTo(a.score));
    }

    // Pick the strongest "bridge" keywords: prefer shared, fallback to vocab scores
    final bridgeKeywords = <String>[];
    for (final w in shared) {
      if (bridgeKeywords.length >= 3) break;
      bridgeKeywords.add(_capitalize(w));
    }
    for (final vs in vocabScores) {
      if (bridgeKeywords.length >= 3) break;
      if (!bridgeKeywords.any((k) => k.toLowerCase() == vs.word)) {
        bridgeKeywords.add(_capitalize(vs.word));
      }
    }

    // Pick the top identity keyword from each note
    final topA = _pickTopWord(uniqueA.isEmpty ? tokensA : uniqueA);
    final topB = _pickTopWord(uniqueB.isEmpty ? tokensB : uniqueB);

    // ── Title synthesis ──────────────────────────────────────────────────────
    final String title;
    if (shared.isNotEmpty) {
      // There's genuine semantic overlap — name the intersection
      final bridge = _capitalize(shared.first);
      title = '$bridge: Bridging ${_capitalize(topA)} & ${_capitalize(topB)}';
    } else if (bridgeKeywords.isNotEmpty) {
      title = '${bridgeKeywords.first}: The ${_capitalize(topA)}–${_capitalize(topB)} Link';
    } else {
      title = 'Bridge: ${_capitalize(topA)} ↔ ${_capitalize(topB)}';
    }

    // ── Content synthesis ────────────────────────────────────────────────────
    // Build a meaningful connecting sentence from the intersection concepts.
    final labelA = _cleanTitle(titleA).isNotEmpty ? _cleanTitle(titleA) : _capitalize(topA);
    final labelB = _cleanTitle(titleB).isNotEmpty ? _cleanTitle(titleB) : _capitalize(topB);

    final StringBuffer contentBuf = StringBuffer();

    if (shared.length >= 2) {
      final concepts = shared.take(2).map(_capitalize).join(' and ');
      contentBuf.write(
        'Conceptual bridge synthesized between "$labelA" and "$labelB". '
        'Both share the themes of $concepts — suggesting a deeper unifying principle. '
        'Exploring this intersection may reveal how ${_capitalize(topA)} informs ${_capitalize(topB)} through the lens of $concepts.',
      );
    } else if (bridgeKeywords.isNotEmpty) {
      final bridge = bridgeKeywords.first.toLowerCase();
      contentBuf.write(
        'Synthesized connection between "$labelA" and "$labelB". '
        'The concept of $bridge emerges as the latent link in this semantic vector space. '
        'Consider how the principles of ${_capitalize(topA)} might be applied to ${_capitalize(topB)} via $bridge.',
      );
    } else {
      contentBuf.write(
        'Semantic bridge between "$labelA" and "$labelB". '
        'Though these ideas appear distant, their vector midpoint suggests a hidden relationship. '
        'What does ${_capitalize(topA)} share with ${_capitalize(topB)}? This note marks the space to explore.',
      );
    }

    return BridgeResult(title: title, content: contentBuf.toString());
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  static List<String> _extractSignificantWords(String title, String content) {
    final plainContent = tokenizeQuillJson(content);
    final allText = '$title $plainContent';
    final tokens = tokenize(allText);
    // Filter very short or very common words
    return tokens.where((w) => w.length > 3).toList();
  }

  static String _pickTopWord(List<String> words) {
    if (words.isEmpty) return 'concept';
    // Prefer longer, more specific words
    final sorted = [...words]..sort((a, b) => b.length.compareTo(a.length));
    return sorted.first;
  }

  static String _capitalize(String word) {
    if (word.isEmpty) return word;
    return word[0].toUpperCase() + word.substring(1);
  }

  static String _cleanTitle(String title) {
    return title.replaceAll(RegExp(r'[^\w\s]'), '').trim();
  }
}

class _VocabScore {
  final String word;
  final double score;
  _VocabScore(this.word, this.score);
}
