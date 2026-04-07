import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Lumo",
  description: "Geo-Semantic place search prototype with Spring Boot backend",
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
