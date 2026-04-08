from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.cidfonts import UnicodeCIDFont
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle


SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
OUTPUT_DIR = PROJECT_ROOT / "docs" / "reports" / "weekly"
OUTPUT_PATH = OUTPUT_DIR / "SW캡스톤I_4주차_주간보고서.pdf"


def register_font() -> str:
    font_name = "HYGothic-Medium"
    pdfmetrics.registerFont(UnicodeCIDFont(font_name))
    return font_name


FONT_NAME = register_font()


def p(text: str, style: ParagraphStyle) -> Paragraph:
    return Paragraph(text.replace("\n", "<br/>"), style)


def build_styles() -> dict[str, ParagraphStyle]:
    styles = getSampleStyleSheet()
    return {
        "title": ParagraphStyle(
            "title",
            parent=styles["Heading1"],
            fontName=FONT_NAME,
            fontSize=16,
            leading=18,
            alignment=TA_CENTER,
            spaceAfter=2,
        ),
        "subtitle": ParagraphStyle(
            "subtitle",
            parent=styles["Normal"],
            fontName=FONT_NAME,
            fontSize=11,
            leading=13,
            alignment=TA_CENTER,
            spaceAfter=8,
        ),
        "section": ParagraphStyle(
            "section",
            parent=styles["Normal"],
            fontName=FONT_NAME,
            fontSize=9,
            leading=11,
            alignment=TA_LEFT,
            spaceAfter=4,
            spaceBefore=2,
        ),
        "header": ParagraphStyle(
            "header",
            parent=styles["Normal"],
            fontName=FONT_NAME,
            fontSize=8.5,
            leading=10,
            alignment=TA_CENTER,
        ),
        "cell": ParagraphStyle(
            "cell",
            parent=styles["Normal"],
            fontName=FONT_NAME,
            fontSize=8.5,
            leading=10.5,
            alignment=TA_CENTER,
        ),
        "body": ParagraphStyle(
            "body",
            parent=styles["Normal"],
            fontName=FONT_NAME,
            fontSize=8.3,
            leading=10.2,
            alignment=TA_LEFT,
        ),
    }


def base_table_style() -> TableStyle:
    return TableStyle(
        [
            ("GRID", (0, 0), (-1, -1), 0.9, colors.black),
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ("LEFTPADDING", (0, 0), (-1, -1), 4),
            ("RIGHTPADDING", (0, 0), (-1, -1), 4),
            ("TOPPADDING", (0, 0), (-1, -1), 3),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
        ]
    )


def main() -> None:
    styles = build_styles()
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    doc = SimpleDocTemplate(
        str(OUTPUT_PATH),
        pagesize=A4,
        leftMargin=32,
        rightMargin=33,
        topMargin=36,
        bottomMargin=36,
    )

    full_width = doc.width
    col_widths = [full_width / 4] * 4

    story = [
        p("졸업프로젝트 주간보고서", styles["title"]),
        p("SW 캡스톤 I 4 주차 주간 보고서", styles["subtitle"]),
    ]

    info_data = [
        [
            p("팀명", styles["header"]),
            p("강승진", styles["cell"]),
            p("지도 시간", styles["header"]),
            p("1시간", styles["cell"]),
        ],
        [
            p("프로젝트명", styles["header"]),
            p("Lumo", styles["cell"]),
            p("담당 교수", styles["header"]),
            p("김원빈", styles["cell"]),
        ],
        [
            p("팀원", styles["header"]),
            p("강승진", styles["cell"]),
            p("(인)", styles["header"]),
            p("", styles["cell"]),
        ],
    ]

    info_table = Table(info_data, colWidths=col_widths, rowHeights=[20, 64, 20])
    info_table.setStyle(base_table_style())
    story.extend([info_table, Spacer(1, 10)])

    story.append(p("금주 진행 사항 (기간 : 2월 22일 - 2월 28일)", styles["section"]))

    progress_data = [
        [
            p("담당자", styles["header"]),
            p("업무명", styles["header"]),
            p("진행 내용", styles["header"]),
            p("진행률", styles["header"]),
        ],
        [
            p("강승진", styles["cell"]),
            p("키워드 검색 구현", styles["cell"]),
            p(
                "BM25 기반 질의 처리와 기본 검색 API를 구성하고 샘플 장소 데이터에서 "
                "키워드 검색 결과와 랭킹 동작을 확인함.",
                styles["body"],
            ),
            p("85%", styles["cell"]),
        ],
        [
            p("강승진", styles["cell"]),
            p("벡터 검색 실험", styles["cell"]),
            p(
                "Sentence Transformers 기반 질의/문장 임베딩 흐름을 정리하고 "
                "OpenSearch k-NN 인덱스 연동 방식과 의미 검색 실험 환경을 구축함.",
                styles["body"],
            ),
            p("75%", styles["cell"]),
        ],
        [
            p("강승진", styles["cell"]),
            p("검색 결과 비교", styles["cell"]),
            p(
                "키워드 검색과 벡터 검색 결과를 비교하여 질의 유형별 장단점을 정리하고 "
                "Hybrid Search 적용 기준을 도출함.",
                styles["body"],
            ),
            p("70%", styles["cell"]),
        ],
        [
            p("강승진", styles["cell"]),
            p("구조 구체화", styles["cell"]),
            p(
                "FastAPI, OpenSearch, Kakao Map 기반 서비스 흐름을 정리하고 "
                "Lumo 프로젝트의 기술 스택 및 인프라 아키텍처 초안을 문서화함.",
                styles["body"],
            ),
            p("65%", styles["cell"]),
        ],
    ]

    progress_table = Table(
        progress_data,
        colWidths=col_widths,
        rowHeights=[20, 60, 58, 56, 56],
    )
    progress_style = base_table_style()
    progress_style.add("ALIGN", (0, 0), (1, -1), "CENTER")
    progress_style.add("ALIGN", (3, 0), (3, -1), "CENTER")
    progress_table.setStyle(progress_style)
    story.extend([progress_table, Spacer(1, 10)])

    story.append(p("차주 진행 업무", styles["section"]))

    next_data = [
        [
            p("업무명", styles["header"]),
            p("차주 업무 내용", styles["header"]),
            p("담당", styles["header"]),
            p("비고", styles["header"]),
        ],
        [
            p("Hybrid Search 구현", styles["cell"]),
            p(
                "BM25 검색과 벡터 검색 결과를 RRF 방식으로 결합하여 "
                "장소 단위 통합 랭킹 로직을 구현함.",
                styles["body"],
            ),
            p("강승진", styles["cell"]),
            p("핵심", styles["cell"]),
        ],
        [
            p("Geo Ranking 설계", styles["cell"]),
            p(
                "사용자 위치를 반영한 거리 기반 가중치와 반경 필터를 적용하여 "
                "검색 결과 재정렬 기준을 설계함.",
                styles["body"],
            ),
            p("강승진", styles["cell"]),
            p("구현", styles["cell"]),
        ],
        [
            p("API · UI 연결", styles["cell"]),
            p(
                "FastAPI 응답 형식을 정리하고 지도 UI 연동을 위한 결과 데이터 구조와 "
                "표시 항목을 구체화함.",
                styles["body"],
            ),
            p("강승진", styles["cell"]),
            p("연동", styles["cell"]),
        ],
    ]

    next_table = Table(
        next_data,
        colWidths=col_widths,
        rowHeights=[20, 54, 54, 54],
    )
    next_style = base_table_style()
    next_style.add("ALIGN", (0, 0), (0, -1), "CENTER")
    next_style.add("ALIGN", (2, 0), (-1, -1), "CENTER")
    next_table.setStyle(next_style)
    story.append(next_table)

    doc.build(story)


if __name__ == "__main__":
    main()
