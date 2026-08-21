import os
import pickle
from dotenv import load_dotenv


import kagglehub
import pandas as pd
import numpy as np
from sklearn.preprocessing import OneHotEncoder
from sklearn.model_selection import train_test_split
from sklearn.ensemble import HistGradientBoostingRegressor


load_dotenv(override=True)

DATASET_PATH = os.environ.get("DATASET_PATH", "yasserh/nyc-taxi-trip-duration")

path = kagglehub.dataset_download(DATASET_PATH)
df = pd.read_csv(f"{path}/NYC.csv")

df = df.drop(['id'], axis=1)


# Data cleaning

# Trip Duration
LOWER_BOUND = 60
UPPER_BOUND = 3 * 60 * 60
df = df[(df.trip_duration >= LOWER_BOUND) & (df.trip_duration <= UPPER_BOUND)]

# Passenger count
max_passengers_count = 6
min_passengers_count = 1
df = df[(df.passenger_count <= max_passengers_count) & (df.passenger_count >= min_passengers_count)]


# pickup_longitude / pickup_latitude
LON_BOUNDS = (-74.03, -73.75)
LAT_BOUNDS = (40.63, 40.85)

df = df[
    df.pickup_longitude.between(*LON_BOUNDS) &
    df.pickup_latitude.between(*LAT_BOUNDS)
]


# Data Engineer


# vendor_id
encoder = OneHotEncoder(handle_unknown='ignore', sparse_output=False, drop="if_binary")

encoded_values = encoder.fit_transform(df[["vendor_id"]])
new_cols = encoder.get_feature_names_out(["vendor_id"])

df_encoded = pd.DataFrame(encoded_values, columns=new_cols, index=df.index)


df = pd.concat([df.drop(columns=['vendor_id']), df_encoded], axis=1)

#pickup_datetime
df.pickup_datetime = pd.to_datetime(df.pickup_datetime)

df['pickup_hour'] = df.pickup_datetime.dt.hour
df['pickup_dayofweek'] = df.pickup_datetime.dt.dayofweek


# Split Data
FEATURES = ["passenger_count", "pickup_longitude", "pickup_latitude", "vendor_id_2", "pickup_hour", "pickup_dayofweek"]
X = df[FEATURES]
y = np.log1p(df["trip_duration"])

# Train model
model = HistGradientBoostingRegressor()
model.fit(X, y)

with open("nyc_city_taxi.pkl", 'wb') as f:
    pickle.dump(model, f)
