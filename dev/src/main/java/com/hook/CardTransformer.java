package com.hook;
import java.lang.instrument.ClassFileTransformer;
import java.security.ProtectionDomain;
import javassist.*;

public class CardTransformer implements ClassFileTransformer {

    @Override
    public byte[] transform(ClassLoader loader, String className, Class<?> classBeingRedefined, 
                            ProtectionDomain protectionDomain, byte[] classfileBuffer) {
        if (className != null && className.startsWith("open/batoru")) {

        try {
            ClassPool pool = new ClassPool(true);
            pool.insertClassPath(new LoaderClassPath(loader));
            String dottedClassName = className.replace('/', '.');

            if (className != null && className.replace("/", ".").equals("open.batoru.data.CardLoader")) {
                CtClass cc = pool.get(dottedClassName);
                CtMethod loadMethod = cc.getDeclaredMethod("load");
                loadMethod.insertAfter(getCardLoaderLogic());
                byte[] byteCode = cc.toBytecode();
                cc.detach();
                return byteCode;
            }

            if (className != null && className.replace("/", ".").equals("open.batoru.catalog.CardPreview")) {
                CtClass cc = pool.get(dottedClassName);
                CtMethod updateTableMethod = cc.getDeclaredMethod("updateTable");
                updateTableMethod.insertBefore(getCardPreviewLogic());              
                byte[] byteCode = cc.toBytecode();
                cc.detach();
                return byteCode;
                
            }

        } catch (Exception e) {
            e.printStackTrace();
        }
    }
        // 바이트코드를 수정하지 않는 경우 원본 바이트코드를 반환
        return classfileBuffer;
    }

    private String getCardPreviewLogic() {
    return ""
        + "try {"
        + "System.out.println($2);"
        + "    java.util.Map translation = com.hook.DBHelper.getTranslationByImageSet($2);"
        + "    if (translation != null) {"
        + "        String name = (String) translation.get(\"Name\");"
        + "        String desc = (String) translation.get(\"description\");"
        + "        String status = (String) translation.get(\"status\");"
        + "        if (!\"0\".equals(status)) {"
        + "            if (name != null) $1.setName(\"kr\", name);"
        + "            if (desc != null) $1.setDescription(\"kr\", desc);"
        + "        }"
        + "    }"
        + "} catch (Exception e) {"
        + "        System.out.println(\"오류\");"
        + "}";
    }

    private String getCardLoaderLogic() {
        return ""
        + "try {"
        + "    java.util.List cards = open.batoru.data.CardLoader.dataCardObjects;"
        + "    for (int i = 0; i < cards.size(); i++) {"
        + "        open.batoru.data.Card card = (open.batoru.data.Card) cards.get(i);"
        + "        String imageSet = card.getImageSets().getPrimaryImageSet();"
        + "        java.util.Map translation = com.hook.DBHelper.getTranslationByImageSet(imageSet);"
        + "        if (translation != null) {"
        + "            String name = (String) translation.get(\"Name\");"
        + "            String status = (String) translation.get(\"status\");"
        + "            if (!\"0\".equals(status)) {"
        + "                if (name != null) card.setName(\"kr\", name);"
        + "            }"
        + "        }"
        + "    }"
        + "} catch (Exception e) {"
        + "    System.out.println(\"오류\");"
        + "}";
    }

}
