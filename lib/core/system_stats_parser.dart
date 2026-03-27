class SystemStatsResult {
  final double cpuPct;
  final int prevIdle;
  final int prevTotal;
  const SystemStatsResult({
    required this.cpuPct,
    required this.prevIdle,
    required this.prevTotal,
  });
}

class SystemRamResult {
  final int usedMb;
  final int totalMb;
  const SystemRamResult({required this.usedMb, required this.totalMb});
}

class SystemStatsParser {
  static SystemStatsResult parseCpu(
    String statRaw,
    int prevIdle,
    int prevTotal,
  ) {
    final line = statRaw
        .split('\n')
        .firstWhere((l) => l.startsWith('cpu '), orElse: () => '');
    if (line.isEmpty) {
      return SystemStatsResult(
        cpuPct: 0,
        prevIdle: prevIdle,
        prevTotal: prevTotal,
      );
    }
    final nums = line
        .split(RegExp(r'\s+'))
        .skip(1)
        .where((s) => s.isNotEmpty)
        .map(int.parse)
        .toList();
    if (nums.length < 4) {
      return SystemStatsResult(
        cpuPct: 0,
        prevIdle: prevIdle,
        prevTotal: prevTotal,
      );
    }
    final idle = nums[3] + (nums.length > 4 ? nums[4] : 0);
    final total = nums.reduce((a, b) => a + b);
    final dI = idle - prevIdle;
    final dT = total - prevTotal;
    double cpuPct = 0;
    if (dT > 0) {
      cpuPct = (1.0 - dI / dT).clamp(0.0, 1.0);
    }
    return SystemStatsResult(cpuPct: cpuPct, prevIdle: idle, prevTotal: total);
  }

  static SystemRamResult parseRam(String meminfoRaw) {
    int total = 0, avail = 0;
    for (final l in meminfoRaw.split('\n')) {
      final p = l.split(RegExp(r'\s+'));
      if (p.length < 2) continue;
      final v = int.tryParse(p[1]) ?? 0;
      if (l.startsWith('MemTotal:')) total = v;
      if (l.startsWith('MemAvailable:')) avail = v;
    }
    if (total > 0) {
      return SystemRamResult(
        usedMb: (total - avail) ~/ 1024,
        totalMb: total ~/ 1024,
      );
    }
    return const SystemRamResult(usedMb: 0, totalMb: 0);
  }
}
