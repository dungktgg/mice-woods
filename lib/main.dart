import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Required for Clipboard access
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:math';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final state = VocabState(prefs);

  runApp(VocabNotesApp(state: state));
}

class VocabNotesApp extends StatelessWidget {
  final VocabState state;
  const VocabNotesApp({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          return MaterialApp(
            title: 'Vocab Notes',
            debugShowCheckedModeBanner: false,
            themeMode: state.isDarkMode ? ThemeMode.dark : ThemeMode.light,

            // --- LIGHT THEME ---
            theme: ThemeData(
              fontFamily: 'Duolingo',
              brightness: Brightness.light,
              scaffoldBackgroundColor: const Color(0xFFF7F7F7),
              cardColor: Colors.white,
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.black, brightness: Brightness.light),
              appBarTheme: const AppBarTheme(
                backgroundColor: Color(0xFFF7F7F7),
                elevation: 0,
                scrolledUnderElevation: 0,
                iconTheme: IconThemeData(color: Colors.black),
                titleTextStyle: TextStyle(color: Colors.black, fontSize: 24, fontWeight: FontWeight.w900, fontFamily: 'Duolingo'),
              ),
              useMaterial3: true,
            ),

            // --- DARK THEME ---
            darkTheme: ThemeData(
              fontFamily: 'Duolingo',
              brightness: Brightness.dark,
              scaffoldBackgroundColor: const Color(0xFF121212),
              cardColor: const Color(0xFF1E1E1E),
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.white, brightness: Brightness.dark),
              appBarTheme: const AppBarTheme(
                backgroundColor: Color(0xFF121212),
                elevation: 0,
                scrolledUnderElevation: 0,
                iconTheme: IconThemeData(color: Colors.white),
                titleTextStyle: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, fontFamily: 'Duolingo'),
              ),
              useMaterial3: true,
            ),

            home: LibraryScreen(state: state),
          );
        }
    );
  }
}

// --- DATA MODEL ---
class VocabNote {
  final String id;
  String word;
  String meaning;
  DateTime dateAdded;

  VocabNote({
    required this.id,
    required this.word,
    required this.meaning,
    required this.dateAdded,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'word': word,
    'meaning': meaning,
    'dateAdded': dateAdded.toIso8601String(),
  };

  factory VocabNote.fromJson(Map<String, dynamic> json) => VocabNote(
    id: json['id'],
    word: json['word'],
    meaning: json['meaning'],
    dateAdded: DateTime.parse(json['dateAdded']),
  );
}

// --- STATE CONTROLLER ---
class VocabState extends ChangeNotifier {
  final SharedPreferences _prefs;
  List<VocabNote> notes = [];
  bool isDarkMode = false;

  VocabState(this._prefs) {
    _loadData();
  }

  void _loadData() {
    isDarkMode = _prefs.getBool('theme_dark') ?? false;
    final String? data = _prefs.getString('vocab_library');
    if (data != null) {
      final List<dynamic> decoded = json.decode(data);
      notes = decoded.map((e) => VocabNote.fromJson(e)).toList();
    }
    notifyListeners();
  }

  void _saveNotes() {
    _prefs.setString('vocab_library', json.encode(notes.map((e) => e.toJson()).toList()));
    notifyListeners();
  }

  // Exports data into clean, formatted JSON for Gemini/Backup
  String get exportedJson {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(notes.map((e) => e.toJson()).toList());
  }

  // Imports JSON and overwrites the local library
  Future<bool> importJson(String jsonString) async {
    try {
      final List<dynamic> decoded = json.decode(jsonString);
      final importedNotes = decoded.map((e) => VocabNote.fromJson(e)).toList();

      notes = importedNotes;
      _saveNotes();
      return true;
    } catch (e) {
      debugPrint("Error importing JSON: $e");
      return false;
    }
  }

  void toggleTheme() {
    isDarkMode = !isDarkMode;
    _prefs.setBool('theme_dark', isDarkMode);
    notifyListeners();
  }

  void addSingle(String word, String meaning) {
    notes.insert(0, VocabNote(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      word: word.trim(),
      meaning: meaning.trim(),
      dateAdded: DateTime.now(),
    ));
    _saveNotes();
  }

  void updateNote(String id, String newWord, String newMeaning) {
    final index = notes.indexWhere((n) => n.id == id);
    if (index != -1) {
      notes[index].word = newWord.trim();
      notes[index].meaning = newMeaning.trim();
      _saveNotes();
    }
  }

  void deleteNote(String id) {
    notes.removeWhere((n) => n.id == id);
    _saveNotes();
  }

  void addBatch(String bulkText) {
    final lines = bulkText.split(RegExp(r'\r?\n'));
    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;

      String word = line;
      String meaning = '';
      final separators = [' - ', ' : ', ' = ', ':', '-', '='];

      for (var sep in separators) {
        if (line.contains(sep)) {
          final idx = line.indexOf(sep);
          word = line.substring(0, idx).trim();
          meaning = line.substring(idx + sep.length).trim();
          break;
        }
      }

      notes.insert(0, VocabNote(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        word: word,
        meaning: meaning,
        dateAdded: DateTime.now(),
      ));
    }
    _saveNotes();
  }
}

// --- MAIN LIBRARY SCREEN (HOME) ---
class LibraryScreen extends StatefulWidget {
  final VocabState state;
  const LibraryScreen({super.key, required this.state});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String searchQuery = '';

  Widget _buildStaggeredGrid(List<VocabNote> filteredNotes) {
    if (filteredNotes.isEmpty) {
      return Center(
          child: Text(
            searchQuery.isEmpty ? "Your library is empty.\nTap + to add some words!" : "No words found.",
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey, fontSize: 16),
          )
      );
    }

    // Optimized lazy loader for massive lists
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: (filteredNotes.length / 2).ceil(),
      itemBuilder: (context, index) {
        int firstIndex = index * 2;
        int secondIndex = firstIndex + 1;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: NoteCard(note: filteredNotes[firstIndex], state: widget.state)),
            Expanded(
              child: secondIndex < filteredNotes.length
                  ? NoteCard(note: filteredNotes[secondIndex], state: widget.state)
                  : const SizedBox(),
            ),
          ],
        );
      },
    );
  }

  void _launchQuiz(BuildContext context) {
    if (widget.state.notes.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least 4 words to your library to play the multiple choice quiz!')),
      );
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => MultipleChoiceQuizScreen(state: widget.state)));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.state.isDarkMode;
    final iconColor = isDark ? Colors.white : Colors.black;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Library'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.settings),
            tooltip: 'Tools & Settings',
            onSelected: (String choice) async {
              switch (choice) {
                case 'theme':
                  widget.state.toggleTheme();
                  break;
                case 'flashcards':
                  if (widget.state.notes.isEmpty) return;
                  Navigator.push(context, MaterialPageRoute(builder: (_) => FlashcardScreen(state: widget.state)));
                  break;
                case 'quiz':
                  _launchQuiz(context);
                  break;
                case 'export':
                  if (widget.state.notes.isEmpty) return;
                  await Clipboard.setData(ClipboardData(text: widget.state.exportedJson));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Library copied! Paste into AI to check.'),
                      backgroundColor: Colors.green,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  break;
                case 'import':
                  final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
                  final text = clipboardData?.text?.trim() ?? '';

                  if (text.isEmpty) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Clipboard is empty!'), backgroundColor: Colors.orange),
                    );
                    return;
                  }

                  final success = await widget.state.importJson(text);

                  if (!context.mounted) return;
                  if (success) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Library successfully updated!'), backgroundColor: Colors.green),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Invalid JSON format! Could not import.'), backgroundColor: Colors.red),
                    );
                  }
                  break;
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'theme',
                child: Row(
                  children: [
                    Icon(isDark ? Icons.light_mode : Icons.dark_mode, color: iconColor),
                    const SizedBox(width: 12),
                    const Text('Toggle Theme'),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'flashcards',
                child: Row(
                  children: [
                    Icon(Icons.style_outlined, color: iconColor),
                    const SizedBox(width: 12),
                    const Text('Flashcards'),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'quiz',
                child: Row(
                  children: [
                    Icon(Icons.quiz_outlined, color: iconColor),
                    const SizedBox(width: 12),
                    const Text('Multiple Choice Quiz'),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'export',
                child: Row(
                  children: [
                    Icon(Icons.copy_all, color: iconColor),
                    const SizedBox(width: 12),
                    const Text('Export JSON'),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'import',
                child: Row(
                  children: [
                    Icon(Icons.paste, color: iconColor),
                    const SizedBox(width: 12),
                    const Text('Import JSON'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: isDark ? Colors.white : Colors.black,
        foregroundColor: isDark ? Colors.black : Colors.white,
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => AddNoteScreen(state: widget.state)));
        },
        child: const Icon(Icons.add),
      ),
      body: ListenableBuilder(
          listenable: widget.state,
          builder: (context, _) {
            final filteredNotes = widget.state.notes.where((note) {
              return note.word.toLowerCase().contains(searchQuery) ||
                  note.meaning.toLowerCase().contains(searchQuery);
            }).toList();

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search notes...',
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      filled: true,
                      fillColor: isDark ? Colors.grey.shade900 : Colors.grey.shade200,
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                    ),
                    onChanged: (val) => setState(() => searchQuery = val.toLowerCase()),
                  ),
                ),
                Expanded(child: _buildStaggeredGrid(filteredNotes)),
              ],
            );
          }
      ),
    );
  }
}

// --- NOTE CARD WIDGET ---
class NoteCard extends StatelessWidget {
  final VocabNote note;
  final VocabState state;

  const NoteCard({super.key, required this.note, required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => AddNoteScreen(state: state, existingNote: note)));
      },
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.all(4),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: state.isDarkMode ? Colors.grey.shade800 : Colors.grey.shade300),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2))
            ]
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(note.word, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: theme.textTheme.bodyLarge?.color)),
            if (note.meaning.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(note.meaning, style: TextStyle(fontSize: 14, color: state.isDarkMode ? Colors.grey.shade400 : Colors.black54)),
            ]
          ],
        ),
      ),
    );
  }
}

// --- ADD / EDIT / BATCH INPUT SCREEN ---
class AddNoteScreen extends StatefulWidget {
  final VocabState state;
  final VocabNote? existingNote;

  const AddNoteScreen({super.key, required this.state, this.existingNote});

  @override
  State<AddNoteScreen> createState() => _AddNoteScreenState();
}

class _AddNoteScreenState extends State<AddNoteScreen> {
  final wordCtrl = TextEditingController();
  final meaningCtrl = TextEditingController();
  final batchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.existingNote != null) {
      wordCtrl.text = widget.existingNote!.word;
      meaningCtrl.text = widget.existingNote!.meaning;
    }
  }

  void _save(bool isBatch) {
    if (isBatch) {
      if (batchCtrl.text.trim().isEmpty) return;
      widget.state.addBatch(batchCtrl.text);
    } else {
      if (wordCtrl.text.trim().isEmpty) return;
      if (widget.existingNote != null) {
        widget.state.updateNote(widget.existingNote!.id, wordCtrl.text, meaningCtrl.text);
      } else {
        widget.state.addSingle(wordCtrl.text, meaningCtrl.text);
      }
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingNote != null;
    final isDark = widget.state.isDarkMode;
    final primaryBtnColor = isDark ? Colors.white : Colors.black;
    final onPrimaryBtnColor = isDark ? Colors.black : Colors.white;

    return DefaultTabController(
      length: isEditing ? 1 : 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(isEditing ? 'Edit Note' : 'New Note'),
          actions: [
            if (isEditing)
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () {
                  widget.state.deleteNote(widget.existingNote!.id);
                  Navigator.pop(context);
                },
              ),
          ],
          bottom: isEditing ? null : TabBar(
            indicatorColor: isDark ? Colors.white : Colors.black,
            labelColor: isDark ? Colors.white : Colors.black,
            unselectedLabelColor: Colors.grey,
            tabs: const [Tab(text: 'Single Word'), Tab(text: 'Smart Batch Paste')],
          ),
        ),
        body: TabBarView(
          children: [
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  TextField(
                    controller: wordCtrl,
                    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900),
                    decoration: const InputDecoration(hintText: 'Word', border: InputBorder.none),
                  ),
                  const Divider(),
                  Expanded(
                    child: TextField(
                      controller: meaningCtrl,
                      maxLines: null,
                      style: const TextStyle(fontSize: 18),
                      decoration: const InputDecoration(hintText: 'Type your meaning or notes here...', border: InputBorder.none),
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: primaryBtnColor, foregroundColor: onPrimaryBtnColor, padding: const EdgeInsets.symmetric(vertical: 16)),
                      onPressed: () => _save(false),
                      child: const Text('Save Note', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  )
                ],
              ),
            ),
            if (!isEditing)
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: isDark ? Colors.grey.shade900 : Colors.grey.shade200, borderRadius: BorderRadius.circular(12)),
                      child: Text(
                        "Paste a massive list of words here. Use '-', ':', or '=' to separate a word from its meaning (e.g., 'apple - a red fruit'). We'll instantly slice them into separate notes!",
                        style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: TextField(
                        controller: batchCtrl,
                        maxLines: null,
                        style: const TextStyle(fontSize: 16),
                        decoration: const InputDecoration(hintText: 'Paste words here...\n\ndog: a loyal animal\ncat - a sneaky pet\nbird = flies around', border: InputBorder.none),
                      ),
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: primaryBtnColor, foregroundColor: onPrimaryBtnColor, padding: const EdgeInsets.symmetric(vertical: 16)),
                        onPressed: () => _save(true),
                        child: const Text('Process & Save All', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    )
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// --- MULTIPLE CHOICE QUIZ SCREEN ---
class MultipleChoiceQuizScreen extends StatefulWidget {
  final VocabState state;
  const MultipleChoiceQuizScreen({super.key, required this.state});

  @override
  State<MultipleChoiceQuizScreen> createState() => _MultipleChoiceQuizScreenState();
}

class _MultipleChoiceQuizScreenState extends State<MultipleChoiceQuizScreen> {
  late List<VocabNote> _quizWords;
  int _currentIndex = 0;
  int _score = 0;
  late List<String> _currentOptions;
  bool _answered = false;
  String _selectedAnswer = '';

  @override
  void initState() {
    super.initState();
    _setupQuiz();
  }

  void _setupQuiz() {
    _quizWords = List.from(widget.state.notes)..shuffle();
    _generateOptions();
  }

  void _generateOptions() {
    VocabNote currentWord = _quizWords[_currentIndex];
    Set<String> optionsSet = {currentWord.meaning};

    List<VocabNote> shuffledLibrary = List.from(widget.state.notes)..shuffle();
    for (var note in shuffledLibrary) {
      if (optionsSet.length >= 4) break;
      if (note.meaning.trim().isNotEmpty) {
        optionsSet.add(note.meaning);
      }
    }

    int fallback = 1;
    while (optionsSet.length < 4) {
      optionsSet.add("Unknown meaning $fallback");
      fallback++;
    }

    _currentOptions = optionsSet.toList()..shuffle();
    _answered = false;
    _selectedAnswer = '';
  }

  void _submitAnswer(String answer) {
    if (_answered) return;

    setState(() {
      _answered = true;
      _selectedAnswer = answer;
      if (answer == _quizWords[_currentIndex].meaning) {
        _score++;
      }
    });

    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      if (_currentIndex < _quizWords.length - 1) {
        setState(() {
          _currentIndex++;
          _generateOptions();
        });
      } else {
        _showResults();
      }
    });
  }

  void _showResults() {
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text("Quiz Complete!"),
          content: Text("You scored $_score out of ${_quizWords.length}."),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: const Text("Done"),
            )
          ],
        )
    );
  }

  @override
  Widget build(BuildContext context) {
    VocabNote currentWord = _quizWords[_currentIndex];
    final isDark = widget.state.isDarkMode;

    return Scaffold(
      appBar: AppBar(
        title: Text('${_currentIndex + 1} / ${_quizWords.length}'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(flex: 1),
            Text(
              currentWord.word,
              style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Select the correct meaning',
              style: TextStyle(fontSize: 16, color: isDark ? Colors.grey.shade400 : Colors.grey.shade700),
              textAlign: TextAlign.center,
            ),
            const Spacer(flex: 2),
            ..._currentOptions.map((option) {
              Color buttonColor = Theme.of(context).cardColor;
              Color textColor = Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black;

              if (_answered) {
                if (option == currentWord.meaning) {
                  buttonColor = isDark ? Colors.green.shade800 : Colors.green.shade200;
                  textColor = isDark ? Colors.white : Colors.black;
                } else if (option == _selectedAnswer) {
                  buttonColor = isDark ? Colors.red.shade900 : Colors.red.shade200;
                  textColor = isDark ? Colors.white : Colors.black;
                }
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: buttonColor,
                    foregroundColor: textColor,
                    padding: const EdgeInsets.all(20),
                    alignment: Alignment.centerLeft,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 1,
                  ),
                  onPressed: () => _submitAnswer(option),
                  child: Text(option, style: const TextStyle(fontSize: 16)),
                ),
              );
            }),
            const Spacer(flex: 1),
          ],
        ),
      ),
    );
  }
}

// --- FLASHCARD REVIEW SCREEN ---
class FlashcardScreen extends StatefulWidget {
  final VocabState state;
  const FlashcardScreen({super.key, required this.state});

  @override
  State<FlashcardScreen> createState() => _FlashcardScreenState();
}

class _FlashcardScreenState extends State<FlashcardScreen> {
  late List<VocabNote> practiceNotes;
  int currentIndex = 0;
  bool isFlipped = false;

  @override
  void initState() {
    super.initState();
    practiceNotes = List.from(widget.state.notes)..shuffle();
  }

  void _nextCard() {
    setState(() {
      if (currentIndex < practiceNotes.length - 1) {
        currentIndex++;
        isFlipped = false;
      } else {
        Navigator.pop(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final note = practiceNotes[currentIndex];
    final isDark = widget.state.isDarkMode;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.grey.shade200,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text('${currentIndex + 1} / ${practiceNotes.length}'),
      ),
      body: Center(
        child: GestureDetector(
          onTap: () => setState(() => isFlipped = !isFlipped),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(opacity: animation, child: child);
            },
            child: Container(
              key: ValueKey(isFlipped),
              width: MediaQuery.of(context).size.width * 0.85,
              height: MediaQuery.of(context).size.height * 0.5,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      isFlipped ? note.meaning : note.word,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: isFlipped ? 24 : 40,
                        fontWeight: isFlipped ? FontWeight.normal : FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 30),
                    Text(
                      isFlipped ? 'Tap to see word' : 'Tap to reveal meaning',
                      style: const TextStyle(color: Colors.grey, fontSize: 14),
                    )
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? Colors.white : Colors.black,
              foregroundColor: isDark ? Colors.black : Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            ),
            onPressed: _nextCard,
            child: Text(currentIndex == practiceNotes.length - 1 ? 'Finish Practice' : 'Next Word', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
        ),
      ),
    );
  }
}