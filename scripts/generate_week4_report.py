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
OUTPUT_PATH = OUTPUT_DIR / "SW캡스톤I_6주차_주간보고서.pdf"


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
        p("SW 캡스톤 I 6 주차 주간 보고서", styles["subtitle"]),
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
            p("Pero", styles["cell"]),
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

    story.append(p("금주 진행 사항 (기간 : 4월 14일 - 4월 20일)", styles["section"]))

    progress_data = [
        [
            p("담당자", styles["header"]),
            p("업무명", styles["header"]),
            p("진행 내용", styles["header"]),
            p("진행률", styles["header"]),
        ],
        [
            p("강승진", styles["cell"]),
            p("핵심 후보 검수", styles["cell"]),
            p(
                "5주차 검증 대상 후보 중 상위 20건을 중심으로 질의별 적합성, "
                "지역 편차, 지도 반응 속도를 수동으로 확인하고 오류 케이스를 정리함.",
                styles["body"],
            ),
            p("70%", styles["cell"]),
        ],
        [
            p("강승진", styles["cell"]),
            p("품질 평가셋 설계", styles["cell"]),
            p(
                "대표 질의셋을 구조화하고, KEYWORD/VECTOR/HYBRID 결과를 "
                "점수 기반으로 비교할 수 있는 평가 항목 초안을 작성함.",
                styles["body"],
            ),
            p("50%", styles["cell"]),
        ],
        [
            p("강승진", styles["cell"]),
            p("검색 로그 저장 설계", styles["cell"]),
            p(
                "요청 로그에 query, mode, 위치 파라미터, topK, 반환 점수 스냅샷을 "
                "기록할 최소 스키마를 정리하여 운영 로그 연동 항목을 확정함.",
                styles["body"],
            ),
            p("35%", styles["cell"]),
        ],
        [
            p("강승진", styles["cell"]),
            p("시연 안정성 정비", styles["cell"]),
            p(
                "서비스 시작/종료, 에러 예외, 지도/검색 동기화 케이스를 한 번에 점검할 "
                "시연 전 체크리스트를 갱신함.",
                styles["body"],
            ),
            p("78%", styles["cell"]),
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
            p("로그 저장 구현", styles["cell"]),
            p(
                "검색 요청/응답 로그를 파일 기반으로 저장하고, 주간 보고에 반영 가능한 "
                "지표(raw score, top 순위, 응답시간)를 추출하도록 구현함.",
                styles["body"],
            ),
            p("강승진", styles["cell"]),
            p("핵심", styles["cell"]),
        ],
        [
            p("평가 지표 자동화", styles["cell"]),
            p(
                "대표 질의셋 정답셋과 정렬 지표를 반영해 수동 비교만으로도 "
                "재현 가능한 품질 점검 스크립트를 준비함.",
                styles["body"],
            ),
            p("강승진", styles["cell"]),
            p("구현", styles["cell"]),
        ],
        [
            p("배포/운영 문서 정비", styles["cell"]),
            p(
                "Docker 실행, 환경변수, 데모 점검 절차를 한 문서로 통합해 "
                "오류 대응 및 재시작 흐름을 정리함.",
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
