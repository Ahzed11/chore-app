EFFORT_POINTS: dict[str, int] = {"easy": 10, "medium": 25, "hard": 50}

# Password strength constraints shared by registration, in-app password
# change, and the operator reset-password CLI (TASK-077).
PASSWORD_MIN_LENGTH = 8
PASSWORD_MAX_LENGTH = 72
