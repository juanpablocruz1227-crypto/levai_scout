enum ResearchDepth {
  quick,
  standard,
  deep,
}

extension ResearchDepthName on ResearchDepth {
  String get label {
    switch (this) {
      case ResearchDepth.quick:
        return 'Rápida';
      case ResearchDepth.standard:
        return 'Normal';
      case ResearchDepth.deep:
        return 'Profunda';
    }
  }
}
