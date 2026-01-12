"""
Script to clear all data from the users table using raw SQL.
WARNING: This will delete all user records from the database.
"""

from sqlalchemy import text
from app.db.database import engine


def clear_users_table():
    """Delete all records from the users table using raw SQL."""
    with engine.connect() as conn:
        try:
            # Count users before deletion
            result = conn.execute(text("SELECT COUNT(*) FROM users"))
            count_before = result.scalar()
            print(f"Found {count_before} user(s) in the database.")

            if count_before == 0:
                print("No users to delete. Exiting.")
                return

            # Delete all users using raw SQL
            result = conn.execute(text("DELETE FROM users"))
            conn.commit()

            print(f"Successfully deleted {count_before} user(s) from the users table.")
        except Exception as e:
            conn.rollback()
            print(f"Error occurred: {e}")
            raise


if __name__ == "__main__":
    print("=" * 50)
    print("WARNING: This will delete ALL users from the database!")
    print("=" * 50)

    response = input("Are you sure you want to continue? (yes/no): ")

    if response.lower() in ["yes", "y"]:
        clear_users_table()
    else:
        print("Operation cancelled.")
