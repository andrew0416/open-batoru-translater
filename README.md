# open-batoru-translater

## Description / 설명
The program is a Java Agent for openBatoru's Korean Patch.<br/>
General Users use `patch` directory for korean patch <br/>
but I also uploaded `dev` directory for the developer.<br/>


이 프로그램은 openBatoru의 한글 패치를 위한 Java Agent 프로그램입니다.<br/>
일반 사용자들은 `patch` 디렉토리의 내용만 필요합니다.<br/>
하지만 개발자들을 위해 `dev` 디렉토리도 업로드하였습니다.<br/>

---

## How to use / 사용 방법
Paste files in `patch` directory and `translate.db` into root directory directory `openBatoru` <br/>
Then, execute `run.vbs`<br/>


`patch` 디렉토리의 파일들과 `translate.db`를 `openBatoru`의 최상위 디렉토리에 붙여넣기합니다.<br/>
그리고 `run.vbs`를 실행합니다.<br/>

---
## translate.db
`translate.db` is `sqlite` database for manage translate text<br/>
but `translate.db` is not prepared yet<br/>
If you need translate.db, you can create `translate` table with below query<br/>

``` sql
CREATE TABLE translate (
    imageSet TEXT PRIMARY KEY,
    Name TEXT,
    description TEXT,
    status INTEGER
);
```
|field|description|
|------|----------------|
|imageSet|imageSet text|
|Name|translated Name text|
|description|translated effect description text|
|status|Status flag. Don't apply translation if status is 0 |

<br/>

`translate.db`은 번역된 텍스트를 다루기 위한 sqlite 데이터베이스입니다.<br/>
https://github.com/andrew0416/open-batoru-translation-ko<br/>
위의 주소에서 한국어버전 `translate.db`를 다운받을 수 있습니다. <br/>
만약 다른 버전의 `translate.db`가 필요하다면, 아래의 쿼리로 `translate` 테이블을 생성할 수 있습니다.<br/>

``` sql
CREATE TABLE translate (
    imageSet TEXT PRIMARY KEY,
    Name TEXT,
    description TEXT,
    status INTEGER
);
```
|필드|설명|
|------|----------------|
|imageSet|imageSet 텍스트|
|Name|번역된 이름 텍스트 |
|description|번역된 효과 설명 텍스트|
|status|상태 플래그, status가 0이라면 번역을 적용하지 않음. |


## 자동 업데이트 
현재의 translate.db는 자동 업데이트 기능이 적용되어 자동적으로 한국어 DB를 적용합니다.<br/>
자동 업데이트를 사용하고싶지 않다면<br/>
`translate.db.update.json`에 `"enabled": false`를 적용하면 됩니다.<br/>

``` json
{
  "enabled": false,
  "mode": "manifest",
  "manifestUrl": "https://raw.githubusercontent.com/andrew0416/open-batoru-translation-ko/main/translate-manifest.json",
  "databasePath": "translate.db",
  "timeoutSeconds": 20,
  "keepBackup": true
}
```

다른 언어로 자동업데이트를 사용하고 싶다면<br/>
https://github.com/andrew0416/open-batoru-translation-ko 를 참조하여 업데이트 레포지토리를 생성하고.<br/>
`manifestUrl`의 주소를 해당 레포지토리의 주소로 교체합니다.<br/>


## LICENSE / 라이선스
MIT LICENSE<br/>
