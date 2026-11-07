/// Word-level comparison between an original passage and its rewrite, grouped into hunks the
/// author can accept or reject one by one.
class DiffHunk {
  /// Text both versions share (a hunk with no change), or the two sides of a change.
  final String before;
  final String after;

  const DiffHunk(this.before, this.after);

  bool get changed => before != after;
}

class WordDiff {
  static final _token = RegExp(r'\s+|[^\s]+');

  /// Splits both texts into words and whitespace, aligns them (longest common subsequence) and
  /// merges neighbouring edits into one hunk. Joining `after` of every hunk gives [updated];
  /// joining `before` gives [original].
  static List<DiffHunk> compute(String original, String updated) {
    final a = _token.allMatches(original).map((m) => m[0]!).toList();
    final b = _token.allMatches(updated).map((m) => m[0]!).toList();

    // ponytail: O(n*m) table, fine for a scene or chapter; swap for Myers if chapters get huge.
    final lcs = List.generate(a.length + 1, (_) => List.filled(b.length + 1, 0));
    for (var i = a.length - 1; i >= 0; i--) {
      for (var j = b.length - 1; j >= 0; j--) {
        lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : (lcs[i + 1][j] >= lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
      }
    }

    final hunks = <DiffHunk>[];
    final same = StringBuffer();
    final del = StringBuffer();
    final add = StringBuffer();

    void flushChange() {
      if (del.isEmpty && add.isEmpty) return;
      hunks.add(DiffHunk(del.toString(), add.toString()));
      del.clear();
      add.clear();
    }

    void flushSame() {
      if (same.isEmpty) return;
      hunks.add(DiffHunk(same.toString(), same.toString()));
      same.clear();
    }

    var i = 0, j = 0;
    while (i < a.length || j < b.length) {
      if (i < a.length && j < b.length && a[i] == b[j]) {
        // A lone space between two edits belongs to the edit, so "a b" → "x y" is one hunk.
        if (a[i].trim().isEmpty && (del.isNotEmpty || add.isNotEmpty) && _nextIsEdit(a, b, i + 1, j + 1)) {
          del.write(a[i]);
          add.write(b[j]);
        } else {
          flushChange();
          same.write(a[i]);
        }
        i++;
        j++;
      } else if (j < b.length && (i == a.length || lcs[i][j + 1] >= lcs[i + 1][j])) {
        flushSame();
        add.write(b[j++]);
      } else {
        flushSame();
        del.write(a[i++]);
      }
    }
    flushChange();
    flushSame();
    return hunks;
  }

  static bool _nextIsEdit(List<String> a, List<String> b, int i, int j) {
    if (i >= a.length && j >= b.length) return false;
    if (i >= a.length || j >= b.length) return true;
    return a[i] != b[j];
  }

  /// The text with each changed hunk resolved: `accepted[k]` picks the new side of the k-th change.
  static String merge(List<DiffHunk> hunks, List<bool> accepted) {
    final out = StringBuffer();
    var change = 0;
    for (final h in hunks) {
      if (!h.changed) {
        out.write(h.after);
      } else {
        out.write(accepted[change++] ? h.after : h.before);
      }
    }
    return out.toString();
  }
}
