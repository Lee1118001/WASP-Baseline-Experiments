from defenses.base import Defense


class NoDefense(Defense):
    name = "none"

    def initialize(self, task=None, agent=None):
        print("[Defense] NoDefense initialized")
