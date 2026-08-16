from abc import ABC


class Defense(ABC):
    name = "base"

    def initialize(self, task=None, agent=None):
        pass

    def preprocess(self, task, context=None):
        return task, context

    def before_action(self, action):
        return True, action

    def after_action(self, action, result):
        return result

    def finalize(self):
        pass
