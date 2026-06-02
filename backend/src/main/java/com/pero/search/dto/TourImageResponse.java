package com.pero.search.dto;

public record TourImageResponse(
        String originImgUrl,
        String smallImageUrl,
        String imgName,
        String serialNum
) {
}
