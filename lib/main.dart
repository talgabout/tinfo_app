import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

void main() {
  runApp(const TinfoApp());
}

class TinfoApp extends StatefulWidget {
  const TinfoApp({super.key});

  @override
  State<TinfoApp> createState() => _TinfoAppState();
}

class _TinfoAppState extends State<TinfoApp> {
  bool _isDarkTheme = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TINFO News',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const _AppScrollBehavior(),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E80F9)),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF7F8FA),
        textTheme: GoogleFonts.interTextTheme(),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E80F9),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0F1218),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      ),
      themeMode: _isDarkTheme ? ThemeMode.dark : ThemeMode.light,
      home: AppShellPage(
        isDarkTheme: _isDarkTheme,
        onToggleTheme: () => setState(() => _isDarkTheme = !_isDarkTheme),
      ),
    );
  }
}

class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.unknown,
      };
}

class NewsItem {
  const NewsItem({
    required this.id,
    required this.category,
    required this.title,
    required this.summary,
    required this.content,
    required this.summaryHtml,
    required this.contentHtml,
    this.imageUrl,
    this.publishedAt,
  });

  final int id;
  final String category;
  final String title;
  final String summary;
  final String content;
  final String summaryHtml;
  final String contentHtml;
  final String? imageUrl;
  final DateTime? publishedAt;

  factory NewsItem.fromJson(Map<String, dynamic> json) {
    final idRaw = json['id'] ?? json['article_id'];
    final title = _asString(
      json['title'] ?? json['name'] ?? json['headline'],
      fallback: 'No title',
    );
    final category = _asString(json['category'] ?? json['category_name'] ?? json['cat_name']);
    final rawSummary = _asString(
      json['summary'] ?? json['introtext'] ?? json['description'] ?? json['excerpt'],
    );
    final rawContent = _asString(
      json['content'] ?? json['fulltext'] ?? json['body'] ?? rawSummary,
    );
    final summary = _stripHtml(rawSummary);
    final content = _stripHtml(rawContent);
    final image = _normalizeImageUrl(_extractImageUrl(json));
    final publishedAtRaw =
        json['published_at'] ?? json['publish_up'] ?? json['created'] ?? json['date'];

    return NewsItem(
      id: _asInt(idRaw),
      category: category,
      title: title,
      summary: summary,
      content: content,
      summaryHtml: rawSummary,
      contentHtml: rawContent,
      imageUrl: image.isEmpty ? null : image,
      publishedAt: DateTime.tryParse(_asString(publishedAtRaw)),
    );
  }
}

class NewsApiService {
  // New custom endpoint package in public_html/endpoint
  static const String _apiBaseUrl = 'https://www.tinfo.kz/endpoint';
  // Legacy fallback (temporary) while endpoint returns 500.
  static const String _legacyWsBaseUrl = 'https://www.tinfo.kz/ws';
  static const int _defaultCatId = 1;

  Future<List<NewsItem>> fetchNews() async {
    try {
      final uri = Uri.parse('$_apiBaseUrl/news.php?categoryId=$_defaultCatId&page=1&limit=30');
      final response = await http.get(uri).timeout(
        const Duration(seconds: 12),
        onTimeout: () => throw Exception('API timeout. Check endpoint URL and server.'),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to load news: ${response.statusCode}');
      }

      final dynamic decoded = jsonDecode(response.body);
      final list = _extractNewsList(decoded);
      return list.map(NewsItem.fromJson).toList();
    } catch (_) {
      final legacy = Uri.parse(
        '$_legacyWsBaseUrl/getArticles.php?catId=$_defaultCatId&page=0&isparent=1',
      );
      final response = await http.get(legacy).timeout(
        const Duration(seconds: 12),
        onTimeout: () => throw Exception('Legacy API timeout.'),
      );
      if (response.statusCode != 200) {
        throw Exception('Failed to load legacy news: ${response.statusCode}');
      }
      final dynamic decoded = jsonDecode(response.body);
      final list = _extractNewsList(decoded);
      return list.map(NewsItem.fromJson).toList();
    }
  }

  Future<List<NewsItem>> fetchFeatured() async {
    try {
      final uri = Uri.parse('$_apiBaseUrl/featured.php?categoryId=$_defaultCatId&limit=5');
      final response = await http.get(uri).timeout(
        const Duration(seconds: 12),
        onTimeout: () => throw Exception('API timeout. Check endpoint URL and server.'),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to load featured news: ${response.statusCode}');
      }

      final dynamic decoded = jsonDecode(response.body);
      final list = _extractNewsList(decoded);
      return list.map(NewsItem.fromJson).toList();
    } catch (_) {
      final fallback = await fetchNews();
      return fallback.where((item) => item.category.isNotEmpty).take(5).toList();
    }
  }

  Future<NewsItem> fetchArticleDetail(int itemId) async {
    try {
      final uri = Uri.parse('$_apiBaseUrl/article.php?id=$itemId');
      final response = await http.get(uri).timeout(
        const Duration(seconds: 12),
        onTimeout: () => throw Exception('API timeout. Check endpoint URL and server.'),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to load article: ${response.statusCode}');
      }

      final dynamic decoded = jsonDecode(response.body);
      final map = _extractResponseMap(decoded);
      if ((map['ok'] as bool?) == false) {
        throw Exception(_asString(map['error'], fallback: 'Article request failed'));
      }

      final dynamic item = map['item'];
      if (item is! Map<String, dynamic>) {
        throw Exception('Article not found');
      }

      return NewsItem.fromJson(item);
    } catch (_) {
      final legacy = Uri.parse('$_legacyWsBaseUrl/getArticleDetail.php?itemid=$itemId');
      final response = await http.get(legacy).timeout(
        const Duration(seconds: 12),
        onTimeout: () => throw Exception('Legacy article API timeout.'),
      );
      if (response.statusCode != 200) {
        throw Exception('Failed to load legacy article: ${response.statusCode}');
      }
      final dynamic decoded = jsonDecode(response.body);
      final list = _extractNewsList(decoded);
      if (list.isEmpty) {
        throw Exception('Article not found');
      }
      return NewsItem.fromJson(list.first);
    }
  }

  Future<List<String>> fetchCategories() async {
    final uri = Uri.parse('$_apiBaseUrl/categories.php?rootId=$_defaultCatId');
    final response = await http.get(uri).timeout(
      const Duration(seconds: 12),
      onTimeout: () => throw Exception('API timeout. Check endpoint URL and server.'),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to load categories: ${response.statusCode}');
    }

    final dynamic decoded = jsonDecode(response.body);
    final map = _extractResponseMap(decoded);
    if ((map['ok'] as bool?) == false) {
      throw Exception(_asString(map['error'], fallback: 'Categories request failed'));
    }

    final dynamic items = map['items'];
    if (items is! List) {
      return <String>[];
    }
    final categories = <String>[];
    for (final raw in items) {
      if (raw is Map<String, dynamic>) {
        final name = _asString(raw['name']).trim();
        if (_isVisibleCategory(name)) {
          categories.add(name);
        }
      }
    }
    return categories;
  }
}

List<Map<String, dynamic>> _extractNewsList(dynamic decoded) {
  final map = _extractResponseMap(decoded);
  if ((map['ok'] as bool?) == false) {
    throw Exception(_asString(map['error'], fallback: 'News request failed'));
  }

  final dynamic data = map['items'] ?? map['data'] ?? map['news'];
  if (data is List) {
    return data.whereType<Map<String, dynamic>>().toList();
  }

  if (decoded is List) {
    return decoded.whereType<Map<String, dynamic>>().toList();
  }

  throw Exception('Unexpected API response format');
}

Map<String, dynamic> _extractResponseMap(dynamic decoded) {
  if (decoded is Map<String, dynamic>) {
    return decoded;
  }
  return <String, dynamic>{};
}

int _asInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }
  return 0;
}

String _asString(dynamic value, {String fallback = ''}) {
  if (value == null) {
    return fallback;
  }
  if (value is String) {
    return value;
  }
  return value.toString();
}

String _stripHtml(String input) {
  if (input.isEmpty) {
    return input;
  }

  // Decode common entities first, then strip tags.
  var cleaned = input
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll(RegExp(r'<[^>]*>'), ' ');

  cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  return cleaned;
}

String _formatDate(DateTime? value) {
  if (value == null) {
    return '';
  }
  final local = value.toLocal();
  const months = <String>[
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря',
  ];
  final day = local.day.toString();
  final month = months[local.month - 1];
  final year = local.year.toString();
  return '$day $month $year';
}

String _formatDateFromSource(NewsItem article) {
  return _formatDate(article.publishedAt);
}

String _extractImageUrl(Map<String, dynamic> json) {
  final direct = _asString(
    json['image'] ??
        json['featureImg'] ??
        json['feature_image'] ??
        json['featureImage'] ??
        json['image_url'] ??
        json['image_intro'] ??
        json['image_fulltext'] ??
        json['thumbnail'],
  );
  if (direct.isNotEmpty) {
    return direct;
  }

  final dynamic imageObject = json['images'];
  if (imageObject is Map<String, dynamic>) {
    final fromMap = _asString(
      imageObject['large'] ??
          imageObject['medium'] ??
          imageObject['small'] ??
          imageObject['intro'] ??
          imageObject['full'],
    );
    if (fromMap.isNotEmpty) {
      return fromMap;
    }
  }

  return '';
}

String _normalizeImageUrl(String value) {
  if (value.isEmpty) {
    return '';
  }
  final trimmed = value.trim();
  if (!(trimmed.startsWith('http://') || trimmed.startsWith('https://'))) {
    return '';
  }
  var canonical = trimmed
      .replaceFirst('http://', 'https://')
      .replaceAll('://tinfo.kz', '://www.tinfo.kz');

  final uri = Uri.tryParse(canonical);
  if (uri != null) {
    // Normalize all legacy media hosts to current site domain.
    if (uri.path.startsWith('/media/k2/')) {
      canonical = 'https://www.tinfo.kz${uri.path}';
    }
  }

  // Route image loading through endpoint proxy for stable Flutter web rendering.
  if (canonical.contains('www.tinfo.kz/endpoint/image.php?src=')) {
    return canonical;
  }
  return 'https://www.tinfo.kz/endpoint/image.php?src=${Uri.encodeComponent(canonical)}';
}

const Set<String> _hiddenCategories = <String>{
  'Жаңалықтар',
  'Igaming',
  'iGaming',
};

bool _isVisibleCategory(String value) {
  final name = value.trim();
  if (name.isEmpty) {
    return false;
  }
  final normalized = name.toLowerCase();
  return !_hiddenCategories.any((hidden) => hidden.toLowerCase() == normalized);
}

class AppShellPage extends StatefulWidget {
  const AppShellPage({
    super.key,
    required this.isDarkTheme,
    required this.onToggleTheme,
  });

  final bool isDarkTheme;
  final VoidCallback onToggleTheme;

  @override
  State<AppShellPage> createState() => _AppShellPageState();
}

class _AppShellPageState extends State<AppShellPage> {
  int _selectedTab = 0;
  bool _isHomeMenuOpen = false;
  String _discoverSelectedCategory = 'Все';
  final Set<int> _savedIds = <int>{};
  final Map<int, NewsItem> _savedItems = <int, NewsItem>{};

  void _toggleSaved(NewsItem item) {
    setState(() {
      if (_savedIds.contains(item.id)) {
        _savedIds.remove(item.id);
        _savedItems.remove(item.id);
      } else {
        _savedIds.add(item.id);
        _savedItems[item.id] = item;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      NewsListPage(
        isDiscoverMode: false,
        onViewAllTap: () => setState(() => _selectedTab = 1),
        savedIds: _savedIds,
        onToggleSaved: _toggleSaved,
        isDarkTheme: widget.isDarkTheme,
        onToggleTheme: widget.onToggleTheme,
        isMenuOpen: _isHomeMenuOpen,
        onMenuOpenChanged: (value) => setState(() => _isHomeMenuOpen = value),
        onMenuCategoryTap: (category) {
          setState(() {
            _discoverSelectedCategory = category;
            _isHomeMenuOpen = false;
            _selectedTab = 1;
          });
        },
      ),
      NewsListPage(
        isDiscoverMode: true,
        savedIds: _savedIds,
        onToggleSaved: _toggleSaved,
        isDarkTheme: widget.isDarkTheme,
        onToggleTheme: widget.onToggleTheme,
        initialDiscoverCategory: _discoverSelectedCategory,
      ),
      _SavedView(
        items: _savedItems.values.toList(),
        onToggleSaved: _toggleSaved,
        onOpen: (item) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => NewsDetailsPage(
                item: item,
                isSaved: _savedIds.contains(item.id),
                onToggleSaved: () => _toggleSaved(item),
              ),
            ),
          );
        },
      ),
      _InfoView(
        isDarkTheme: widget.isDarkTheme,
        onToggleTheme: widget.onToggleTheme,
      ),
    ];

    return Scaffold(
      body: pages[_selectedTab],
      bottomNavigationBar: (_selectedTab == 0 && _isHomeMenuOpen)
          ? null
          : _BottomNavBar(
              selectedIndex: _selectedTab,
              onSelect: (value) => setState(() => _selectedTab = value),
            ),
    );
  }
}

class NewsListPage extends StatefulWidget {
  const NewsListPage({
    super.key,
    required this.isDiscoverMode,
    this.onViewAllTap,
    required this.savedIds,
    required this.onToggleSaved,
    required this.isDarkTheme,
    required this.onToggleTheme,
    this.isMenuOpen = false,
    this.onMenuOpenChanged,
    this.onMenuCategoryTap,
    this.initialDiscoverCategory = 'Все',
  });

  final bool isDiscoverMode;
  final VoidCallback? onViewAllTap;
  final Set<int> savedIds;
  final ValueChanged<NewsItem> onToggleSaved;
  final bool isDarkTheme;
  final VoidCallback onToggleTheme;
  final bool isMenuOpen;
  final ValueChanged<bool>? onMenuOpenChanged;
  final ValueChanged<String>? onMenuCategoryTap;
  final String initialDiscoverCategory;

  @override
  State<NewsListPage> createState() => _NewsListPageState();
}

class _NewsListPageState extends State<NewsListPage> {
  final NewsApiService _api = NewsApiService();
  late Future<_FeedData> _feedFuture;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _feedFuture = _loadFeed();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _feedFuture = _loadFeed();
    });
    await _feedFuture;
  }

  Future<_FeedData> _loadFeed() async {
    final news = await _api.fetchNews();

    List<NewsItem> featured = <NewsItem>[];
    try {
      featured = await _api.fetchFeatured();
    } catch (_) {
      // Keep home feed usable even if featured endpoint temporarily fails.
      featured = <NewsItem>[];
    }

    List<String> categories = <String>[];
    try {
      categories = await _api.fetchCategories();
    } catch (_) {
      categories = news
          .map((item) => item.category.trim())
          .where(_isVisibleCategory)
          .toSet()
          .toList();
    }

    return _FeedData(
      news: news,
      featured: featured,
      categories: categories,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<_FeedData>(
          future: _feedFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 180),
                  Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      'Не удалось загрузить новости.\n${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              );
            }

            final data = snapshot.data ?? const _FeedData(news: [], featured: [], categories: []);
            final news = data.news;
            if (news.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 180),
                  Center(child: Text('Пока нет новостей')),
                ],
              );
            }

            return widget.isDiscoverMode
                ? _DiscoverView(
                    news: news,
                    onOpen: _openDetails,
                    categories: data.categories,
                    initialCategory: widget.initialDiscoverCategory,
                  )
                : Stack(
                    children: [
                      _HomeView(
                        news: news,
                        featured: data.featured,
                        onOpen: _openDetails,
                        onViewAllTap: widget.onViewAllTap,
                        isDarkTheme: widget.isDarkTheme,
                        onToggleTheme: widget.onToggleTheme,
                        isMenuOpen: widget.isMenuOpen,
                        onMenuTap: () => widget.onMenuOpenChanged?.call(!widget.isMenuOpen),
                      ),
                      _FullScreenMenu(
                        isOpen: widget.isMenuOpen,
                        onClose: () => widget.onMenuOpenChanged?.call(false),
                        onCategoryTap: (category) => widget.onMenuCategoryTap?.call(category),
                        categories: data.categories,
                      ),
                    ],
                  );
          },
        ),
      ),
    );
  }

  void _openDetails(NewsItem item) {
    if (widget.isMenuOpen) {
      widget.onMenuOpenChanged?.call(false);
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NewsDetailsPage(
          item: item,
          isSaved: widget.savedIds.contains(item.id),
          onToggleSaved: () => widget.onToggleSaved(item),
        ),
      ),
    );
  }
}

class _HomeView extends StatelessWidget {
  const _HomeView({
    required this.news,
    required this.featured,
    required this.onOpen,
    this.onViewAllTap,
    required this.isDarkTheme,
    required this.onToggleTheme,
    required this.isMenuOpen,
    required this.onMenuTap,
  });

  final List<NewsItem> news;
  final List<NewsItem> featured;
  final ValueChanged<NewsItem> onOpen;
  final VoidCallback? onViewAllTap;
  final bool isDarkTheme;
  final VoidCallback onToggleTheme;
  final bool isMenuOpen;
  final VoidCallback onMenuTap;

  @override
  Widget build(BuildContext context) {
    final top = featured.isEmpty ? news.take(5).toList() : featured.take(5).toList();
    final rest = news;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        _TopBar(
          isMenuOpen: isMenuOpen,
          onMenuTap: onMenuTap,
          isDarkTheme: isDarkTheme,
          onToggleTheme: onToggleTheme,
        ),
        const SizedBox(height: 18),
        _SectionHeader(title: 'Главные новости', onTapAll: onViewAllTap),
        const SizedBox(height: 12),
        _BreakingCarousel(items: top, onOpen: onOpen),
        const SizedBox(height: 18),
        _SectionHeader(title: 'Лента новостей', onTapAll: onViewAllTap),
        const SizedBox(height: 8),
        ...rest.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _FeedRow(item: item, onTap: () => onOpen(item)),
          ),
        ),
      ],
    );
  }
}

class _FeedData {
  const _FeedData({
    required this.news,
    required this.featured,
    required this.categories,
  });

  final List<NewsItem> news;
  final List<NewsItem> featured;
  final List<String> categories;
}

class _BreakingCarousel extends StatefulWidget {
  const _BreakingCarousel({required this.items, required this.onOpen});

  final List<NewsItem> items;
  final ValueChanged<NewsItem> onOpen;

  @override
  State<_BreakingCarousel> createState() => _BreakingCarouselState();
}

class _BreakingCarouselState extends State<_BreakingCarousel> {
  late final PageController _pageController;
  static const int _kLoopBase = 10000;
  late int _virtualPage;

  @override
  void initState() {
    super.initState();
    final count = widget.items.isEmpty ? 1 : widget.items.length;
    _virtualPage = _kLoopBase * count;
    _pageController = PageController(
      viewportFraction: 0.84,
      initialPage: _virtualPage,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return const SizedBox.shrink();
    }
    final itemCount = widget.items.length;
    final realIndex = _realIndexFromVirtual(_virtualPage, itemCount);

    return Column(
      children: [
        SizedBox(
          height: 236,
          child: PageView.builder(
            controller: _pageController,
            itemCount: null,
            onPageChanged: (index) {
              _virtualPage = index;
              setState(() {});
            },
            itemBuilder: (context, index) {
              final mapped = _realIndexFromVirtual(index, itemCount);
              final item = widget.items[mapped];
              return AnimatedBuilder(
                animation: _pageController,
                builder: (context, child) {
                  double scaleX = 0.95;
                  double scaleY = 0.92;
                  if (_pageController.hasClients && _pageController.position.hasContentDimensions) {
                    final page = _pageController.page ?? _virtualPage.toDouble();
                    final diff = (page - index).abs();
                    scaleX = (1 - (diff * 0.06)).clamp(0.92, 1.0);
                    scaleY = (1 - (diff * 0.10)).clamp(0.86, 1.0);
                  } else if (index == _virtualPage) {
                    scaleX = 1.0;
                    scaleY = 1.0;
                  }
                  return Transform.scale(
                    scaleX: scaleX,
                    scaleY: scaleY,
                    child: child,
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: _HeroNewsCard(item: item, onTap: () => widget.onOpen(item)),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ...List.generate(widget.items.length, (index) {
              final active = index == realIndex;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                height: 8,
                width: active ? 22 : 8,
                decoration: BoxDecoration(
                  color: active ? const Color(0xFF2E80F9) : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10),
                ),
              );
            }),
          ],
        ),
      ],
    );
  }

  int _realIndexFromVirtual(int virtualIndex, int itemCount) {
    if (itemCount <= 1) {
      return 0;
    }
    var mod = virtualIndex % itemCount;
    if (mod < 0) {
      mod += itemCount;
    }
    return mod;
  }
}

class _DiscoverView extends StatefulWidget {
  const _DiscoverView({
    required this.news,
    required this.onOpen,
    required this.categories,
    required this.initialCategory,
  });

  final List<NewsItem> news;
  final ValueChanged<NewsItem> onOpen;
  final List<String> categories;
  final String initialCategory;

  @override
  State<_DiscoverView> createState() => _DiscoverViewState();
}

class _DiscoverViewState extends State<_DiscoverView> {
  String _selectedCategory = 'Все';

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory;
  }

  @override
  void didUpdateWidget(covariant _DiscoverView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialCategory != widget.initialCategory) {
      _selectedCategory = widget.initialCategory;
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = <String>['Все', ...widget.categories];
    if (!categories.contains(_selectedCategory)) {
      _selectedCategory = 'Все';
    }
    final filtered = _selectedCategory == 'Все'
        ? widget.news
        : widget.news.where((e) => e.category == _selectedCategory).toList();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        Text('Лента новостей', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 12),
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: categories
                .map(
                  (cat) => _TopicChip(
                    label: cat,
                    selected: _selectedCategory == cat,
                    onTap: () => setState(() => _selectedCategory = cat),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 12),
        ...filtered.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _FeedRow(item: item, onTap: () => widget.onOpen(item)),
          ),
        ),
      ],
    );
  }
}

class _SavedView extends StatelessWidget {
  const _SavedView({
    required this.items,
    required this.onOpen,
    required this.onToggleSaved,
  });

  final List<NewsItem> items;
  final ValueChanged<NewsItem> onOpen;
  final ValueChanged<NewsItem> onToggleSaved;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(
        child: Text('В избранном пока пусто'),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        Text('Избранное', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 12),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _FeedRow(
              item: item,
              onTap: () => onOpen(item),
              trailing: IconButton(
                onPressed: () => onToggleSaved(item),
                icon: const Icon(Icons.bookmark, color: Color(0xFF2E80F9)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BottomNavBar extends StatelessWidget {
  const _BottomNavBar({
    required this.selectedIndex,
    required this.onSelect,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;

  static const _items = <(IconData, String)>[
    (Icons.home_outlined, 'Главная'),
    (Icons.public_outlined, 'Лента'),
    (Icons.bookmark_border, 'Избр.'),
    (Icons.info_outline_rounded, 'Инфо'),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 86,
        child: Container(
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF111723) : Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: isDark ? const Color(0x66000000) : const Color(0x12000000),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: List.generate(_items.length, (index) {
              final item = _items[index];
              final selected = index == selectedIndex;
              return Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => onSelect(index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? const Color(0xFF2E80F9) : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        AnimatedScale(
                          duration: const Duration(milliseconds: 180),
                          scale: selected ? 1.05 : 0.95,
                          curve: Curves.easeOutBack,
                          child: Icon(
                            item.$1,
                            size: 22,
                            color: selected
                                ? Colors.white
                                : (isDark ? const Color(0xFF8C95A3) : Colors.black38),
                          ),
                        ),
                        TweenAnimationBuilder<double>(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                          tween: Tween<double>(begin: 0, end: selected ? 1 : 0),
                          builder: (context, value, child) {
                            return ClipRect(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                widthFactor: value,
                                child: Opacity(opacity: value, child: child),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(
                              item.$2,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                                fontSize: 14,
                                height: 1.0,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _InfoView extends StatelessWidget {
  const _InfoView({
    required this.isDarkTheme,
    required this.onToggleTheme,
  });

  final bool isDarkTheme;
  final VoidCallback onToggleTheme;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      children: [
        Center(
          child: SvgPicture.asset(
            isDarkTheme ? 'assets/tinfo_logo_dark.svg' : 'assets/tinfo_logo.svg',
            width: 360,
            height: 88,
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'О tinfo.kz',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Text(
          'TINFO.kz — городской новостной портал с актуальными материалами по Талдыкоргану, области Жетiсу и Казахстану.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.35),
        ),
        const SizedBox(height: 20),
        Text(
          'Контакты',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          'Сайт: https://www.tinfo.kz',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Email: info@tinfo.kz',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'WhatsApp: 8 778 000 0877',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 28),
        _ThemeToggleButton(
          isDarkTheme: isDarkTheme,
          onToggleTheme: onToggleTheme,
        ),
      ],
    );
  }
}

class _ThemeToggleButton extends StatelessWidget {
  const _ThemeToggleButton({
    required this.isDarkTheme,
    required this.onToggleTheme,
  });

  final bool isDarkTheme;
  final VoidCallback onToggleTheme;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggleTheme,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: isDarkTheme ? const Color(0xFF2E80F9) : const Color(0xFFE8EEF8),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Icon(
                isDarkTheme ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                key: ValueKey<bool>(isDarkTheme),
                color: isDarkTheme ? Colors.white : const Color(0xFF2E80F9),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isDarkTheme ? 'Темная тема включена' : 'Переключить на темную тему',
                style: TextStyle(
                  color: isDarkTheme ? Colors.white : const Color(0xFF2E80F9),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: isDarkTheme ? Colors.white : const Color(0xFF2E80F9),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.isMenuOpen,
    required this.onMenuTap,
    required this.isDarkTheme,
    required this.onToggleTheme,
  });

  final bool isMenuOpen;
  final VoidCallback onMenuTap;
  final bool isDarkTheme;
  final VoidCallback onToggleTheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _MenuToggleButton(
          isOpen: isMenuOpen,
          onTap: onMenuTap,
        ),
        const Spacer(),
        const _TopBarIconButton(icon: Icons.search_rounded),
        const SizedBox(width: 12),
        _TopBarIconButton(
          icon: isDarkTheme ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
          onTap: onToggleTheme,
        ),
      ],
    );
  }
}

class _MenuToggleButton extends StatelessWidget {
  const _MenuToggleButton({
    required this.isOpen,
    required this.onTap,
  });

  final bool isOpen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark ? const Color(0xFF202938) : const Color(0xFFF1F2F4),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 56,
          height: 56,
          child: Center(
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              tween: Tween<double>(begin: 0, end: isOpen ? 1 : 0),
              builder: (context, value, child) {
                return AnimatedIcon(
                  icon: AnimatedIcons.menu_close,
                  progress: AlwaysStoppedAnimation<double>(value),
                  color: isDark ? Colors.white : Colors.black87,
                  size: 30,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _FullScreenMenu extends StatelessWidget {
  const _FullScreenMenu({
    required this.isOpen,
    required this.categories,
    required this.onClose,
    required this.onCategoryTap,
  });

  final bool isOpen;
  final List<String> categories;
  final VoidCallback onClose;
  final ValueChanged<String> onCategoryTap;

  @override
  Widget build(BuildContext context) {
    const itemHeight = 56.0;
    const visibleItems = 7;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return IgnorePointer(
      ignoring: !isOpen,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 240),
        opacity: isOpen ? 1 : 0,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          offset: isOpen ? Offset.zero : const Offset(-0.04, 0),
          child: Material(
            color: isDark ? const Color(0xFF0D1420).withValues(alpha: 0.98) : const Color(0xFFFDFDFE),
            child: SafeArea(
              child: Stack(
                children: [
                  Positioned(
                    top: 12,
                    left: 16,
                    child: _MenuToggleButton(
                      isOpen: true,
                      onTap: onClose,
                    ),
                  ),
                  Column(
                    children: [
                      const SizedBox(height: 88),
                      Expanded(
                        child: Center(
                          child: SizedBox(
                            height: itemHeight * visibleItems,
                            child: ShaderMask(
                              blendMode: BlendMode.dstIn,
                              shaderCallback: (rect) => const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: <Color>[
                                  Color(0xFFFFFFFF),
                                  Color(0xFFFFFFFF),
                                  Color(0xCCFFFFFF),
                                  Color(0x00FFFFFF),
                                ],
                                stops: <double>[0.0, 0.72, 0.9, 1.0],
                              ).createShader(rect),
                              child: ScrollConfiguration(
                                behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                                child: ListView.separated(
                                  physics: const BouncingScrollPhysics(),
                                  itemCount: categories.length,
                                  separatorBuilder: (_, index) => const SizedBox(height: 8),
                                  itemBuilder: (context, index) {
                                    final label = categories[index];
                                    return SizedBox(
                                      height: itemHeight - 8,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: () => onCategoryTap(label),
                                        child: Center(
                                          child: Text(
                                            label,
                                            textAlign: TextAlign.center,
                                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color: isDark
                                                      ? const Color(0xFFE6EAF2)
                                                      : const Color(0xFF1A1A1A),
                                                ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'tinfo.kz',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: isDark ? const Color(0xFF9AA3B3) : const Color(0xFF6E6E73),
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.onTapAll});

  final String title;
  final VoidCallback? onTapAll;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const Spacer(),
        TextButton(
          onPressed: onTapAll,
          child: const Text('Все', style: TextStyle(color: Color(0xFF2E80F9))),
        ),
      ],
    );
  }
}

class _TopBarIconButton extends StatelessWidget {
  const _TopBarIconButton({
    required this.icon,
    this.onTap,
  });

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark ? const Color(0xFF202938) : const Color(0xFFF1F2F4),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 56,
          height: 56,
          child: Center(
            child: Icon(icon, color: isDark ? Colors.white : Colors.black87, size: 30),
          ),
        ),
      ),
    );
  }
}

class _GlassCircleIconButton extends StatelessWidget {
  const _GlassCircleIconButton({
    required this.icon,
    this.onTap,
  });

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 11, sigmaY: 11),
        child: Material(
          color: const Color(0x3A000000),
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 50,
              height: 50,
              child: Icon(icon, color: Colors.white, size: 25),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroNewsCard extends StatelessWidget {
  const _HeroNewsCard({required this.item, required this.onTap});

  final NewsItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Container(
        width: 320,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: item.imageUrl == null ? Colors.black87 : null,
        ),
        child: Stack(
          children: [
            if (item.imageUrl != null)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: _ResilientNetworkImage(
                    url: item.imageUrl!,
                    fit: BoxFit.cover,
                    preferredSize: _NewsImageSize.large,
                  ),
                ),
              ),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0xE6000000)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TagPill(text: item.category.isEmpty ? 'Новости' : item.category),
                  const Spacer(),
                  Text(
                    _formatDate(item.publishedAt),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xE6FFFFFF),
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w500,
                      height: 1.18,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedRow extends StatelessWidget {
  const _FeedRow({
    required this.item,
    required this.onTap,
    this.trailing,
  });

  final NewsItem item;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? const Color(0xFFEAF0F8) : const Color(0xFF1A1A1A);
    final categoryColor = isDark ? const Color(0xFFA5AFBF) : const Color(0xFF707070);
    final dateColor = isDark ? const Color(0xFF9AA3B3) : const Color(0xFF666666);
    return Material(
      color: isDark ? const Color(0xFF1A2331) : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 96,
                  height: 84,
                  child: item.imageUrl == null
                      ? Container(color: isDark ? const Color(0xFF263041) : Colors.grey.shade300)
                      : _ResilientNetworkImage(
                          url: item.imageUrl!,
                          fit: BoxFit.cover,
                          preferredSize: _NewsImageSize.small,
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.category.isEmpty ? 'Новости' : item.category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: categoryColor,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: titleColor,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _formatDate(item.publishedAt),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: dateColor),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TopicChip extends StatelessWidget {
  const _TopicChip({
    required this.label,
    this.selected = false,
    this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap?.call(),
        showCheckmark: false,
        labelStyle: TextStyle(
          color: selected ? Colors.white : (isDark ? const Color(0xFF9BA5B6) : const Color(0xFF8E8E93)),
          fontWeight: FontWeight.w500,
        ),
        backgroundColor: isDark ? const Color(0xFF1A2331) : Colors.white,
        selectedColor: const Color(0xFF2E80F9),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _TagPill extends StatelessWidget {
  const _TagPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF2E80F9),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ResilientNetworkImage extends StatefulWidget {
  const _ResilientNetworkImage({
    required this.url,
    this.fit = BoxFit.cover,
    this.preferredSize = _NewsImageSize.large,
  });

  final String url;
  final BoxFit fit;
  final _NewsImageSize preferredSize;

  @override
  State<_ResilientNetworkImage> createState() => _ResilientNetworkImageState();
}

class _ResilientNetworkImageState extends State<_ResilientNetworkImage> {
  late List<String> _candidates;
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _resetCandidates();
  }

  @override
  void didUpdateWidget(covariant _ResilientNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.preferredSize != widget.preferredSize) {
      _resetCandidates();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_candidates.isEmpty) {
      return _placeholder();
    }
    return Image.network(
      _candidates[_current],
      fit: widget.fit,
      gaplessPlayback: true,
      filterQuality: FilterQuality.low,
      webHtmlElementStrategy: WebHtmlElementStrategy.never,
      errorBuilder: (context, error, stackTrace) {
        if (_current < _candidates.length - 1) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _current++);
            }
          });
          return _placeholder();
        }
        return _placeholder();
      },
    );
  }

  void _resetCandidates() {
    _current = 0;
    _candidates = _buildCandidates(widget.url, widget.preferredSize);
  }

  List<String> _buildCandidates(String url, _NewsImageSize preferredSize) {
    final candidates = <String>[];
    if (preferredSize == _NewsImageSize.small) {
      candidates.add(_replaceImageSize(url, '_S.jpg'));
      candidates.add(_replaceImageSize(url, '_M.jpg'));
      candidates.add(_replaceImageSize(url, '_L.jpg'));
    } else {
      candidates.add(_replaceImageSize(url, '_L.jpg'));
      candidates.add(_replaceImageSize(url, '_M.jpg'));
      candidates.add(_replaceImageSize(url, '_S.jpg'));
    }
    if (candidates.isEmpty) {
      candidates.add(url);
    }
    return candidates.toSet().toList();
  }

  String _replaceImageSize(String sourceUrl, String targetSuffix) {
    if (sourceUrl.contains(RegExp(r'_[LMS]\.jpg', caseSensitive: false))) {
      return sourceUrl.replaceAll(RegExp(r'_[LMS]\.jpg', caseSensitive: false), targetSuffix);
    }
    return sourceUrl;
  }

  Widget _placeholder() {
    return Container(
      color: Colors.grey.shade300,
      alignment: Alignment.center,
      child: const Icon(Icons.image_outlined, color: Colors.white70),
    );
  }
}

enum _NewsImageSize { small, large }

class NewsDetailsPage extends StatefulWidget {
  const NewsDetailsPage({
    super.key,
    required this.item,
    required this.isSaved,
    required this.onToggleSaved,
  });

  final NewsItem item;
  final bool isSaved;
  final VoidCallback onToggleSaved;

  @override
  State<NewsDetailsPage> createState() => _NewsDetailsPageState();
}

class _NewsDetailsPageState extends State<NewsDetailsPage> {
  final NewsApiService _api = NewsApiService();
  late Future<NewsItem> _detailsFuture;
  final ScrollController _scrollController = ScrollController();
  double _topRadius = 30;
  double _heroBlurSigma = 0;
  double _heroDimOpacity = 0;
  late bool _isSavedLocal;

  @override
  void initState() {
    super.initState();
    _detailsFuture = _api.fetchArticleDetail(widget.item.id);
    _scrollController.addListener(_handleScroll);
    _isSavedLocal = widget.isSaved;
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    final offset = _scrollController.hasClients ? _scrollController.offset : 0;
    // Smoothly flatten top corners as article content scrolls up.
    final nextRadius = (30 - (offset / 3)).clamp(0, 30).toDouble();
    // Gradually blur and dim the hero zone while user scrolls down.
    final nextBlur = (offset / 22).clamp(0, 9).toDouble();
    final nextDim = (offset / 380).clamp(0, 0.35).toDouble();
    if (((nextRadius - _topRadius).abs() > 0.5 ||
            (nextBlur - _heroBlurSigma).abs() > 0.2 ||
            (nextDim - _heroDimOpacity).abs() > 0.02) &&
        mounted) {
      setState(() {
        _topRadius = nextRadius;
        _heroBlurSigma = nextBlur;
        _heroDimOpacity = nextDim;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: FutureBuilder<NewsItem>(
        future: _detailsFuture,
        builder: (context, snapshot) {
          final article = snapshot.data ?? widget.item;
          return CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverAppBar(
                expandedHeight: 420,
                pinned: false,
                leading: const SizedBox.shrink(),
                leadingWidth: 0,
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      article.imageUrl == null
                          ? Container(color: Colors.black87)
                          : _ResilientNetworkImage(
                              url: article.imageUrl!,
                              fit: BoxFit.cover,
                              preferredSize: _NewsImageSize.large,
                            ),
                      Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x10000000), Color(0xE6000000)],
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: BackdropFilter(
                            filter: ImageFilter.blur(
                              sigmaX: _heroBlurSigma,
                              sigmaY: _heroBlurSigma,
                            ),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 120),
                              color: Colors.black.withValues(alpha: _heroDimOpacity),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: MediaQuery.of(context).padding.top + 10,
                        left: 16,
                        right: 16,
                        child: Row(
                          children: [
                            _GlassCircleIconButton(
                              icon: Icons.arrow_back_ios_new_rounded,
                              onTap: () => Navigator.of(context).maybePop(),
                            ),
                            const Spacer(),
                            _GlassCircleIconButton(
                              icon: _isSavedLocal ? Icons.bookmark : Icons.bookmark_border,
                              onTap: () {
                                setState(() => _isSavedLocal = !_isSavedLocal);
                                widget.onToggleSaved();
                              },
                            ),
                            const SizedBox(width: 10),
                            _GlassCircleIconButton(
                              icon: Icons.share_outlined,
                              onTap: () {
                                final shareText =
                                    '${article.title}\n\nhttps://www.tinfo.kz\n\n${_formatDateFromSource(article)}';
                                SharePlus.instance.share(
                                  ShareParams(
                                    text: shareText,
                                    subject: article.title,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        left: 20,
                        right: 20,
                        bottom: 52,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _TagPill(text: article.category.isEmpty ? 'Новости' : article.category),
                            const SizedBox(height: 12),
                            Text(
                              article.title,
                              maxLines: 5,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                                fontSize: 23,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _formatDateFromSource(article),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xE6FFFFFF),
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            const SizedBox(height: 4),
                          ],
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: -1,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                          height: 18,
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF101825) : Colors.white,
                            borderRadius: BorderRadius.vertical(top: Radius.circular(_topRadius)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF101825) : Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(_topRadius)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (snapshot.hasError)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: Text(
                              'Полный текст временно недоступен, показана краткая версия.',
                              style: TextStyle(color: Colors.redAccent),
                            ),
                          ),
                        Html(
                          data: article.contentHtml.isEmpty ? article.summaryHtml : article.contentHtml,
                          style: {
                            'body': Style(
                              margin: Margins.zero,
                              padding: HtmlPaddings.zero,
                              fontSize: FontSize(16),
                              lineHeight: const LineHeight(1.3),
                              color: isDark ? const Color(0xFFEAF0F8) : Colors.black,
                            ),
                            'p': Style(
                              margin: Margins.only(bottom: 12),
                              fontSize: FontSize(16),
                              lineHeight: const LineHeight(1.3),
                              color: isDark ? const Color(0xFFEAF0F8) : Colors.black,
                            ),
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
