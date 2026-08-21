from datetime import datetime
from enum import IntEnum

from pydantic import BaseModel, Field

class Vendor(IntEnum):
    VENDOR_1 = 1
    VENDOR_2 = 2


class PredictRequest(BaseModel):
    passenger_count: int = Field(..., ge=1, le=6, description="Passenger count of the trip")
    pickup_longitude: float = Field(..., ge=-74.03, le=-73.75, description="Longitude of pickup bound on NYC Taxi trips")
    pickup_latitude: float = Field(..., ge=40.63, le=40.85, description="Latitude of pickup bound on NYC Taxi trips")
    vendor_id: Vendor = Field(..., description="Vendor of the trip")
    pickup_datetime: datetime = Field(..., description="Pickup datetime of the trip")
   

class PredictResponse(BaseModel):
   trip_duration: float = Field(..., description="Trip duration in seconds")