import type { Metadata } from "next";
import { Inter, Manrope } from "next/font/google";
import "./globals.css";

const manrope = Manrope({
  subsets: ["latin"],
  variable: "--font-manrope",
});

const inter = Inter({
  subsets: ["latin"],
  variable: "--font-inter",
});

export const metadata: Metadata = {
  title: "Pero | 메타데이터와 위치로 찾는 장소 검색",
  description: "사용 목적과 위치를 함께 반영해 주변 장소를 추천하는 검색 서비스",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="ko">
      <body className={`${manrope.variable} ${inter.variable}`}>{children}</body>
    </html>
  );
}
