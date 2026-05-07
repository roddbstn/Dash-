import 'package:flutter/material.dart';
import 'package:dash_mobile/theme.dart';

class DbHistoryTab extends StatelessWidget {
  final List<dynamic> injectedDrafts;

  const DbHistoryTab({super.key, required this.injectedDrafts});

  @override
  Widget build(BuildContext context) {
    if (injectedDrafts.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 48, 24, 16),
            child: Text(
              'DB 내역',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF222222)),
            ),
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history_rounded, size: 64, color: AppColors.border.withValues(alpha: 0.8)),
                  const SizedBox(height: 16),
                  const Text(
                    '기입한 DB가 없어요',
                    style: TextStyle(color: Color(0xFFADB5BD), fontSize: 16, fontWeight: FontWeight.w400),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '확장프로그램으로 DB를 기입하면 여기 기록돼요',
                    style: TextStyle(color: Color(0xFFADB5BD), fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }


    // 날짜별 그룹핑 (updated_at 기준, KST 변환)
    final Map<String, List<dynamic>> groups = {};
    const dayNames = ['일', '월', '화', '수', '목', '금', '토'];

    for (final d in injectedDrafts) {
      final raw = (d['updated_at'] ?? d['created_at'] ?? '') as String;
      final dt = raw.isNotEmpty
          ? DateTime.parse(raw.endsWith('Z') ? raw : '${raw}Z').toLocal()
          : DateTime.now();
      final dayName = dayNames[dt.weekday % 7];
      final key = '${dt.year}.${dt.month}.${dt.day} ($dayName)';
      groups.putIfAbsent(key, () => []).add(d);
    }

    final sections = groups.entries.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 48, 24, 16),
          child: Text(
            'DB 내역',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF222222)),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            itemCount: sections.length,
            itemBuilder: (context, sectionIndex) {
              final section = sections[sectionIndex];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 16, bottom: 8, left: 4),
                    child: Text(
                      section.key,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF8B95A1),
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  ...section.value.map((d) => _HistoryCard(draft: d)),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HistoryCard extends StatefulWidget {
  final dynamic draft;
  const _HistoryCard({required this.draft});

  @override
  State<_HistoryCard> createState() => _HistoryCardState();
}

class _HistoryCardState extends State<_HistoryCard> {
  bool _expanded = false;

  String get _injectedTimeStr {
    final raw = widget.draft['reviewed_at'] ?? widget.draft['updated_at'];
    if (raw == null || (raw as String).isEmpty) return '기입 완료';
    try {
      final dt = DateTime.parse(raw.endsWith('Z') ? raw : '${raw}Z').toLocal();
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m 기입 완료';
    } catch (_) {
      return '기입 완료';
    }
  }

  String get _dateTimeStr {
    const dayNames = ['일', '월', '화', '수', '목', '금', '토'];
    final startRaw = widget.draft['startTime'] ?? widget.draft['start_time'];
    final endRaw = widget.draft['endTime'] ?? widget.draft['end_time'];
    if (startRaw == null || endRaw == null) return '-';
    try {
      final start = DateTime.parse(startRaw.replaceAll(' ', 'T'));
      final end = DateTime.parse(endRaw.replaceAll(' ', 'T'));
      final dayName = dayNames[start.weekday % 7];
      final datePart = '${start.month}.${start.day} ($dayName)';
      final startT = '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
      final endT = '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';
      return '$datePart $startT ~ $endT';
    } catch (_) {
      return '-';
    }
  }


  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    final caseName = d['caseName'] ?? d['case_name'] ?? '미지정';
    final dong = d['dong'] ?? '';
    final serviceDescription = d['serviceDescription'] ?? d['service_description'] ?? '';
    final agentOpinion = d['agentOpinion'] ?? d['agent_opinion'] ?? '';
    final serviceCategory = d['service_category'] ?? d['serviceCategory'] ?? '';
    final serviceName = d['service_name'] ?? d['serviceName'] ?? '';
    final serviceFullName = serviceCategory.isNotEmpty && serviceName.isNotEmpty
        ? '$serviceCategory :: $serviceName'
        : (serviceName.isNotEmpty ? serviceName : '-');
    final rawServiceType = d['service_type'] ?? d['serviceType'] ?? '';
    final serviceTypeDisplay = rawServiceType == '아보전' ? '아보전서비스' : (rawServiceType.isNotEmpty ? rawServiceType : '-');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFF2F4F6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 헤더
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                '$caseName 아동 사례',
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF222222)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (dong.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Text(dong, style: const TextStyle(fontSize: 12, color: Color(0xFF8B95A1))),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _injectedTimeStr,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF8B95A1)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 요약 정보
                  _InfoRow(label: '제공일시', value: _dateTimeStr),
                  _InfoRow(label: '제공서비스', value: serviceFullName),
                  _InfoRow(label: '제공방법', value: d['method'] ?? '-'),
                ],
              ),
            ),

            // 상세 보기 토글
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFFF2F4F6))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      _expanded ? '접기' : '상세 보기',
                      style: const TextStyle(fontSize: 13, color: Color(0xFF8B95A1), fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 4),
                    Icon(_expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                        size: 16, color: const Color(0xFFADB5BD)),
                  ],
                ),
              ),
            ),

            if (_expanded) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InfoRow(label: '대상자', value: d['target'] ?? '-'),
                    _InfoRow(label: '제공구분', value: d['provision_type'] ?? '-'),
                    _InfoRow(label: '서비스제공유형', value: serviceTypeDisplay),
                    _InfoRow(label: '제공장소', value: d['location'] ?? '-'),
                    const SizedBox(height: 12),
                    const Text('서비스 내용', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF4E5968))),
                    const SizedBox(height: 6),
                    Text(serviceDescription.isNotEmpty ? serviceDescription : '-', style: const TextStyle(fontSize: 13, height: 1.6, color: Color(0xFF4E5968))),
                    const SizedBox(height: 12),
                    const Text('상담원 소견', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF4E5968))),
                    const SizedBox(height: 6),
                    Text(agentOpinion.isNotEmpty ? agentOpinion : '-', style: const TextStyle(fontSize: 13, height: 1.6, color: Color(0xFF4E5968))),
                  ],
                ),
              ),
            ],

          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF8B95A1), fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 12, color: Color(0xFF4E5968), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
