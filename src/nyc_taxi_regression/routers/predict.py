from typing import Annotated

from fastapi import APIRouter, Depends

from ..schemas.predict import PredictRequest, PredictResponse
from ..services.predict import TripDurationPredictor, get_predictor

router = APIRouter(prefix="/predict", tags=["predict"])


@router.post("", response_model=PredictResponse, description="Predict NYC Taxi trip duration")
def predict_trip_duration(
    predict_request: PredictRequest,
    predictor: Annotated[TripDurationPredictor, Depends(get_predictor)],
) -> PredictResponse:
    return predictor.predict(predict_request)
