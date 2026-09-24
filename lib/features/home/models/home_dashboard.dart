class HomeDashboard {
  final RateHistory? rateHistory;
  final InvestSection? investSection;
  final LearningSection? learningSection;
  final FooterInfo? footerInfo;

  HomeDashboard({
    this.rateHistory,
    this.investSection,
    this.learningSection,
    this.footerInfo,
  });

  factory HomeDashboard.fromJson(Map<String, dynamic> json) {
    return HomeDashboard(
      rateHistory: json['rate_history'] != null
          ? RateHistory.fromJson(json['rate_history'])
          : null,
      investSection: json['invest_sections'] != null
          ? InvestSection.fromJson(json['invest_sections'])
          : null,
      learningSection: json['learning_sections'] != null
          ? LearningSection.fromJson(json['learning_sections'])
          : null,
      footerInfo: json['footer_info'] != null
          ? FooterInfo.fromJson(json['footer_info'])
          : null,
    );
  }
}

class RateHistory {
  final String title;
  final String startYear;
  final num startRate;
  final String endYear;
  final num endRate;
  final String highlightText;

  RateHistory({
    required this.title,
    required this.startYear,
    required this.startRate,
    required this.endYear,
    required this.endRate,
    required this.highlightText,
  });

  factory RateHistory.fromJson(Map<String, dynamic> json) {
    // API may return rates as strings ("4865.00") or numbers — handle both.
    num _parseRate(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v;
      return num.tryParse(v.toString()) ?? 0;
    }

    return RateHistory(
      title: json['title'] ?? '',
      startYear: json['start_year'] ?? '',
      startRate: _parseRate(json['start_rate']),
      endYear: json['end_year'] ?? '',
      endRate: _parseRate(json['end_rate']),
      highlightText: json['highlight_text'] ?? '',
    );
  }
}

class InvestSection {
  final String title;
  final String subtitle;
  final List<InvestBlock> blocks;

  InvestSection({required this.title, this.subtitle = 'Small steps today,\nBig rewards tomorrow.', required this.blocks});

  factory InvestSection.fromJson(Map<String, dynamic> json) {
    return InvestSection(
      title: json['title'] ?? '',
      subtitle: json['subtitle'] ?? 'Small steps today,\nBig rewards tomorrow.',
      blocks: (json['blocks'] as List?)
              ?.map((e) => InvestBlock.fromJson(e))
              .toList() ??
          [],
    );
  }
}

class InvestBlock {
  final String? image;

  InvestBlock({this.image});

  factory InvestBlock.fromJson(Map<String, dynamic> json) {
    return InvestBlock(
      image: json['image'],
    );
  }
}

class LearningSection {
  final String title;
  final List<LearningBanner> banners;

  LearningSection({required this.title, required this.banners});

  factory LearningSection.fromJson(Map<String, dynamic> json) {
    return LearningSection(
      title: json['title'] ?? '',
      banners: (json['banners'] as List?)
              ?.map((e) => LearningBanner.fromJson(e))
              .toList() ??
          [],
    );
  }
}

class LearningBanner {
  final int? id;
  final String? title;
  final String image;
  final String? url;

  LearningBanner({
    this.id,
    this.title,
    required this.image,
    this.url,
  });

  factory LearningBanner.fromJson(Map<String, dynamic> json) {
    return LearningBanner(
      id: json['id'],
      title: json['title'],
      image: json['image'] ?? '',
      url: json['url'],
    );
  }
}

class FooterInfo {
  final String title;
  final String subtitle;
  final List<ComplianceItem> compliance;
  final String cin;
  final String copyright;

  FooterInfo({
    required this.title,
    required this.subtitle,
    required this.compliance,
    required this.cin,
    required this.copyright,
  });

  factory FooterInfo.fromJson(Map<String, dynamic> json) {
    return FooterInfo(
      title: json['title'] ?? '',
      subtitle: json['subtitle'] ?? '',
      compliance: (json['compliance'] as List?)
              ?.map((e) => ComplianceItem.fromJson(e))
              .toList() ??
          [],
      cin: json['cin'] ?? '',
      copyright: json['copyright'] ?? '',
    );
  }
}

class ComplianceItem {
  /// Supports both 'image' (new API) and 'icon' (old API) keys.
  final String image;
  final String label;

  ComplianceItem({required this.image, required this.label});

  factory ComplianceItem.fromJson(Map<String, dynamic> json) {
    return ComplianceItem(
      image: json['image'] ?? json['icon'] ?? '',
      label: json['label'] ?? '',
    );
  }
}
