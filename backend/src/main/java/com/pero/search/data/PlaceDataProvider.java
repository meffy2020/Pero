package com.pero.search.data;

public interface PlaceDataProvider {
    String id();

    String providerName();

    boolean isEnabled();

    PlaceDataLoadResult load();
}

