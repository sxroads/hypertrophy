from sqlalchemy import Column, String, Boolean, DateTime, Integer
from sqlalchemy.sql import func
import uuid
from app.db.database import Base
from app.db.types import GUID


class User(Base):
    __tablename__ = "users"

    user_id = Column(GUID(), primary_key=True, default=uuid.uuid4)
    email = Column(String, unique=True, nullable=True, index=True)
    password_hash = Column(String, nullable=True)
    is_anonymous = Column(Boolean, default=False, nullable=False)
    gender = Column(String, nullable=True)  # "male" or "female"
    age = Column(Integer, nullable=True)
    created_at = Column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
