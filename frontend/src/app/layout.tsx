import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Lumo | 리뷰와 위치로 찾는 장소 검색",
  description: "사용 목적과 위치를 함께 반영해 주변 장소를 추천하는 검색 서비스",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="ko">
      <body>{children}</body>
    </html>
  );
}
