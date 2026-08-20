import os
import pathlib
import pickle
from functools import lru_cache
from zoneinfo import ZoneInfo

import numpy as np
import pandas as pd

from ..schemas.predict import PredictRequest, PredictResponse, Vendor

NY = ZoneInfo("America/New_York")

DEFAULT_MODEL_PATH = pathlib.Path(__file__).parents[3] / "nyc_city_taxi.pkl"


class TripDurationPredictor:
    def __init__(self, model):
        self.model = model
        self.features = list(model.feature_names_in_)

    @classmethod
    def from_path(cls, path: pathlib.Path) -> "TripDurationPredictor":
        with open(path, "rb") as f:
            return cls(pickle.load(f))

    def _to_frame(self, request: PredictRequest) -> pd.DataFrame:
        
        pickup = request.pickup_datetime
        if pickup.tzinfo:
            pickup = pickup.astimezone(NY)

        row = {
            "passenger_count": request.passenger_count,
            "pickup_longitude": request.pickup_longitude,
            "pickup_latitude": request.pickup_latitude,
            "vendor_id_2": float(request.vendor_id == Vendor.VENDOR_2),
            "pickup_hour": pickup.hour,
            "pickup_dayofweek": pickup.weekday(),
        }
        return pd.DataFrame([row])[self.features]

    def predict(self, request: PredictRequest) -> PredictResponse:
        # model uses log1p(duracao); expm1 return segundos
        duration_log = self.model.predict(self._to_frame(request))[0]
        return PredictResponse(trip_duration=float(np.expm1(duration_log)))


@lru_cache(maxsize=1)
def get_predictor() -> TripDurationPredictor:
    path = pathlib.Path(os.environ.get("MODEL_PATH", DEFAULT_MODEL_PATH))
    return TripDurationPredictor.from_path(path)
